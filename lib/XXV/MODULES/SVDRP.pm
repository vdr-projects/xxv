package XXV::MODULES::SVDRP;

use Tools;
use Locale::gettext;
use strict;


$|++;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'SVDRP',
        Prereq => {
            'Net::Telnet'  => 'Net::Telnet allows you to make client connections to a TCP port and do network I/O',
        },
        Description => gettext('This module a telnet client for sdvrp.'),
        Version => '0.93',
        Date => '2007-02-21',
        Author => 'xpix',
        Preferences => {
            VdrHost => {
                description => gettext('Name of the host that runs vdr'),
                default     => 'localhost',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            VdrPort => {
                description => gettext('SVDRP-port of the running vdr client'),
                default     => 2001,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            timeout => {
                description => gettext('Connection timeout defines after how many seconds an unrequited connection is terminated.'),
                default     => 60,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            sstatus => {
                description => gettext('Status from svdrp'),
                short       => 'ss',
                callback    => sub{ $obj->status(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            scommand => {
                description => gettext('Send a command to svdrp'),
                short       => 'sc',
                callback    => sub{ $obj->scommand(@_) },
                Level       => 'admin',
                DenyClass   => 'remote',
            },
        },
    };
    return $args;
}

# ------------------
sub new {
# ------------------
	my($class, %attr) = @_;
	my $self = {};
	bless($self, $class);

    # paths
    $self->{paths} = delete $attr{'-paths'};

	# who am I
    $self->{MOD} = $self->module;

    # all configvalues to $self without parents (important for ConfigModule)
    map {
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_};
        $self->{$_} = $self->{MOD}->{Preferences}->{$_}->{default} unless($self->{$_});
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    $self->{COMMANDS} = [];

	return $self;
}

# ------------------
sub queue_cmds {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $cmd = shift  || 'CALL';

    if($cmd eq 'CALL') {
        my $queue = delete $obj->{COMMANDS};
        $obj->{COMMANDS} = [];
        return $obj->command($queue);
    } elsif($cmd eq 'COUNT') {
        return scalar @{$obj->{COMMANDS}};
    } else {
        push(@{$obj->{COMMANDS}}, $cmd);
    }
}

# ------------------
sub command {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $cmd = shift;

    my $host = $obj->{VdrHost};
    my $port = $obj->{VdrPort};

    my $data;
    my $line;
    my @commands = ();
    push(@commands, (ref $cmd eq 'ARRAY' ? @$cmd : $cmd));

    unless(scalar @commands > 0) {
      error ('No Commands!');
      return undef;
    }
    push(@commands, "quit");

    $obj->{ERROR} = 0;

    # Put Command follow quit and read Output
    my $telnet = Net::Telnet->new ( Telnetmode => 0,
                                   Timeout    => $obj->{timeout},
                                   Errmode    => 'return');

    if(!$telnet or !$telnet->open(Host => $host, Port => $port)){
      error sprintf("Couldn't connect to svdrp-socket %s:%s! %s",$host,$port,$telnet ? $telnet->errmsg : $!);
      return undef;
    }

    # read first line 
    do {
      $line = $telnet->getline;
      last unless $line;
      chomp($line);
      push(@$data, $line);
    } while($line =~ /^\d\d\d\-/);

    unless(scalar @$data){
      error sprintf("Couldn't read data from svdrp-socket %s:%s! %s",$host,$port,$telnet ? $telnet->errmsg : $!);
      return undef;
    }

    main::getVdrVersion($1)
        if($data->[0] =~ /SVDRP\s+VideoDiskRecorder\s+(\d\.\d\.\d+)[\;|\-]/);

    # send commando queue
    foreach my $command (@commands) {
        $telnet->buffer_empty; #clear buffer
        # send command
        if(!$telnet->print($command)) {
          error sprintf("Couldn't send svdrp-command '%s' to %s:%s! %s",$command,$host,$port,$telnet ? $telnet->errmsg : $!);
          return undef;      
        }
        # read response
        do {
          $line = $telnet->getline;
          last unless $line;
          chomp($line);

          if($line =~ /^(\d{3})\s+(.+)/ && (int($1) >= 500)) {
            my $msg = sprintf("Error at command '%s' to %s:%s! %s", $command,$host,$port, $2);
            error($msg);
            $obj->{ERROR} .= $msg . "\n";
          }

          push(@$data, $line);
        } while($line =~ /^\d\d\d\-/);
    }

    # close socket
    $telnet->close();

    foreach my $command (@commands) {
      event(sprintf('Call command "%s" on svdrp %s.', $command, $obj->{ERROR} ? " failed" : "successful")) 
        if($command ne "quit");
    }
    return \@$data;
}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return;

    my $erg = $obj->command('stat disk');
    $console->msg($erg, $obj->err)
        if(ref $console);
}

# ------------------
sub scommand {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $text = shift || return $console->err(gettext("No Command! Please use scommand 'cmd'"));

    my $erg = $obj->command($text);
    $console->msg($erg, $obj->err);
}


# ------------------
sub err {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    return $obj->{ERROR};
}

1;
