package XXV::MODULES::LOGREAD;

use strict;

use Tools;
use Locale::gettext;
use XXV::OUTPUT::HTML::PUSH;

$|++;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'LOGREAD',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module read the xxv log file and show it on console.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Level => 'admin',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            tail => {
                description => sprintf(gettext("Path of command '%s'"),'tail'),
                default     => '/usr/bin/tail',
                type        => 'file',
                required    => gettext('This is required!'),
            },
            rows => {
                description => gettext('How much lines to display?'),
                default     => '100',
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            syslog => {
                description => gettext('Path of syslog file?'),
                default     => '/var/log/syslog',
                type        => 'file',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            logger => {
                description => gettext("Display the last log entries"),
                short       => 'lg',
                callback    => sub{ $obj->logger(@_) },
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

	return $self;
}

# ------------------
sub logger {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $logname = shift || 'standard';
    my $params  = shift || {};

    $obj->{logfiles} = {
        main    => {
            # Path to logfile
            logfile => $obj->{paths}->{LOGFILE},
                       #24 (14870) [22:29:08 09/22/05] CHANNELS: Read and register Channels ...
            # Regular expression for every loglines
            regex   => qr/^(\d+)\s+\((\d+)\)\s+\[(\d+\-\d+\-\d+ \d+\:\d+\:\d+)\]\s+(.+?)$/s,
            # Fields List for describe the rows
            fields => [qw/Nr Typ Time Message/],
            # Callback for coloring rows
            display=> sub{
                my $typ = $_[0][1];
                return 'black'  if($typ < 200);
                return 'green'  if($typ < 300);
                return 'blue'   if($typ < 400);
                return 'brown'  if($typ < 500);
                return 'red'    if($typ >= 500);
            },
            # Maximum letters for truncate in template
            maxlet=> 50,
        },
        syslog    => {
            logfile => $obj->{syslog},
                       #Sep 23 00:35:01 vdr /USR/SBIN/CRON[16971]: (root) CMD (/usr/bin/weatherng.sh)
            regex   => qr/^(.+?)\s+(\d+)\s+(\d+\:\d+\:\d+)\s+(.+?)\s+(.+)/s,
            fields => [qw/Month MDay Time Prg Message/],
            display=> sub{
                my $txt = $_[0][-1];
                return 'red' if($txt =~ /ERROR/si);
                return 'blue' if($txt =~ /WARNING/si);
                return 'green' if($txt =~ /INFO/si);
                return 'black';
            },
            maxlet=> 80,
        },
    };

    if( ! ref $obj->{logfiles}->{$logname}) {
        return $console->err(sprintf("The log with the name %s does not exist! Please use '%s'!", $logname, join("' or '", keys %{$obj->{logfiles}})));
    }

    my $logfile = $obj->{logfiles}->{$logname}->{logfile};
    my @out = $obj->tail($logfile);

    return $console->msg(undef, sprintf(gettext("Can't read log file %s!"), $logfile))
        unless(scalar @out);

    my $output = $obj->parseLogOutput($obj->{logfiles}->{$logname}, \@out);

    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                          $atime,$mtime,$ctime,$blksize,$blocks)
                              = stat($logfile);

    $console->table($output, {
        type    => $logname,
        logfile => $logfile,
        Size    => convert($size),
        LastChanged => scalar localtime($mtime),
        full    => $params->{full},
        color   => $obj->{logfiles}->{$logname}->{display},
        maxlet  => $obj->{logfiles}->{$logname}->{maxlet},
    });
    return 1;
}

# ------------------
sub tail {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $logfile = shift  || return error ('No Logfile!' );
    my $rows = shift  || $obj->{rows};

    my $cmd = sprintf('%s --lines=%d %s', $obj->{tail}, $rows, $logfile);
    my @out = (`$cmd`);
    return @out;
}


# ------------------
sub parseLogOutput {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $log = shift  || return error ('No Prefs for logfile!' );
    my $out = shift  || return;

    my $regex = $log->{regex};
    $obj->{logbuf} = undef;

    my $ret = [];
    foreach my $line (@$out) {
        if(my @d = $line =~ $regex) {
            $obj->parseData($ret, \@d) if($d[0]);
        } else {
            $obj->parseData($ret, $line);
        }
    }
    my @r = reverse @$ret;

    unshift(@r, $log->{fields});
    return \@r;
}

# ------------------
sub parseData {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $ret     = shift || return error('No Referenced Array');
    my $data    = shift || 0;


    if(ref $data eq 'ARRAY') {     # Set Data
        $data->[-1] .= $obj->{logbuf}
            if($obj->{logbuf});
        push(@$ret, $data);
        $obj->{logbuf} = undef;
    } elsif($data) {               # Message (last row, last item) .+ $line
        $obj->{logbuf} .= $data;
    }
    return $ret;
}

1;
