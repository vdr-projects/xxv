package XXV::MODULES::SVDRP;

use Tools;
use strict;


$|++;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'SVDRP',
        Prereq => {
            'Net::Telnet'  => 'Net::Telnet allows you to make client connections to a TCP port and do network I/O',
        },
        Description => gettext('This module module manages connection to video disk recorder.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            timeout => {
                description => gettext('Connection timeout defines after how many seconds an unrequited connection is terminated.'),
                default     => 60,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            vdrlist => {
                description => gettext("List defined video disk recorder."),
                short       => 'vl',
                callback    => sub{ $self->list(@_) },
                Level       => 'admin',
            },
            vdrnew => {
                description => gettext('Create new video disk recorder definition.'),
                short       => 'vn',
                callback    => sub{ $self->create(@_) },
                Level       => 'admin',
            },
            vdrdelete => {
                description => gettext("Delete video disk recorder definition 'id'"),
                short       => 'vd',
                callback    => sub{ $self->delete(@_) },
                Level       => 'admin',
            },
            vdredit => {
                description => gettext("Edit video disk recorder definition 'id'"),
                short       => 've',
                callback    => sub{ $self->edit(@_) },
                Level       => 'admin',
            },
            sstatus => {
                description => gettext('Status from video disk recorder.'),
                short       => 'ss',
                callback    => sub{ $self->status(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            scommand => {
                description => gettext('Send a command to video disk recorder.'),
                short       => 'sc',
                callback    => sub{ $self->scommand(@_) },
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

    $self->{charset} = delete $attr{'-charset'};
    if($self->{charset} eq 'UTF-8'){
      eval 'use utf8';
    }

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
        if($@) {
          my $m = (split(/ /, $_))[0];
          return panic("\nCouldn't load perl module: $m\nPlease install this module on your system:\nperl -MCPAN -e 'install $m'");
        }
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # initialize modul
    my $erg = $self->_init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $self = shift || return error('No object defined!');

    unless($self->{dbh}) {
      panic("Session to database is'nt connected");
      return 0;
    }

    my $version = main::getDBVersion();
    # don't remove old table, if updated rows => warn only
    if(!tableUpdated($self->{dbh},'RECORDER',$version,0)) {
        return 0;
    }

    # Look for table or create this table
    my $erg = $self->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS RECORDER (
          id int unsigned auto_increment NOT NULL,
          active enum('y', 'n') default 'y',
          master enum('y', 'n') default 'n',
          host varchar(100) NOT NULL default 'localhost',
          port smallint unsigned default 2001,
          cards varchar(100) default '',
          PRIMARY KEY (id)
        ) COMMENT = '$version'
    |);

    # The Table is empty? Make a default host ...
    my $first = $self->{dbh}->selectrow_arrayref('SELECT SQL_CACHE count(*) from RECORDER');
    unless($first && $first->[0]) {
        $self->_insert({
            active => 'y',
            master => 'y',
            host => 'localhost',
            port => 2001,
            cards => ''
        });
    }

    return 1;
}

# ------------------
sub _insert {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || return;

    my $sth = $self->{dbh}->prepare('REPLACE INTO RECORDER VALUES (?,?,?,?,?,?)');
    $sth->execute( 
         $data->{id} || 0,
         $data->{active},
         $data->{master},
         $data->{host},
         $data->{port},
         $data->{cards}
     ) or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
}

sub create {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || 0;
    my $data    = shift || 0;

    $self->edit($watcher, $console, $id, $data);
}

sub edit {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || 0;
    my $data    = shift || 0;

    my $default;
    if($id and not ref $data) {
        my $sth = $self->{dbh}->prepare('SELECT SQL_CACHE * from RECORDER where id = ?');
        $sth->execute($id)
            or return $console->err(sprintf(gettext("Definition of video disk recorder '%s' does not exist in the database!"),$id));
        $default = $sth->fetchrow_hashref();
    }

    my $questions = [
        'id' => {
            typ     => 'hidden',
            def     => $default->{id} || 0,
        },
        'active' => {
            typ     => 'confirm',
            def     => $default->{active} || 'y',
            msg     => gettext('Activate this definition'),
        },
        'host' => {
            typ     => 'host',
            msg   => gettext("Host or IP address of video disk recorder"),
            req   => gettext('This is required!'),
            def   => $default->{host} || '',
        },
        'port' => {
            typ     => 'integer',
            msg   => gettext("Used Port of SVDRP"),
            req   => gettext('This is required!'),
            def   => $default->{port} || 2001,
            check   => sub{
                my $value = int(shift);
                if($value > 0 && $value < 65536) {
                    return $value;
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'master' => {
            typ     => 'confirm',
            def     => $default->{master} || 'n',
            msg     => gettext('Use as primary video disk recorder'),
        },
        'cards' => {
            msg   => gettext("List of present source of DVB cards. (eg. S19.2E,S19.2E,T,T )"),
            def   => $default->{cards} || main::getModule('CHANNELS')->buildSourceList($id || $self->primary_hosts()),
        },

    ];

    # Ask Questions
    $data = $console->question(($id ? gettext('Edit video disk recorder definition')
				    : gettext('Create new video disk recorder definition')), $questions, $data);

    if(ref $data eq 'HASH') {

        if($data->{'master'} eq 'y') {
          $self->{dbh}->do("UPDATE RECORDER SET master='n' WHERE master = 'y'");
        }
        $self->_insert($data);

        $self->_deletevdrdata($data->{'id'})  if($data->{'active'} ne 'y');

        delete $self->{Cache};

        debug sprintf('%s video disk recorder definition "%s" is saved%s',
            ($id ? 'New' : 'Changed'),
            $data->{host},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $console->message(gettext('Video disk recorder definition saved!'));
        $console->redirect({url => '?cmd=vdrlist', wait => 1})
            if($console->typ eq 'HTML');
    }
    return 1;
}

sub delete {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id = shift || return $console->err(gettext("No definition of video disk recorder for deletion! Please use sdelete 'id'."));

    my $sth = $self->{dbh}->prepare('delete from RECORDER where id = ?');
    $sth->execute($id)
        or return $console->err(sprintf(gettext("Definition of video disk recorder '%s' does not exist in the database!"),$id));

    $self->_deletevdrdata($id);

    delete $self->{Cache};

    $console->message(sprintf gettext("Definition of video disk recorder are %s deleted."), $id);

    debug sprintf('Delete definition of video disk recorder "%s"%s',
        $id,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    $console->redirect({url => '?cmd=vdrlist', wait => 1})
        if($console->typ eq 'HTML');
}

sub _deletevdrdata {
    my $self = shift || return error('No object defined!');
    my $id = shift;
    
    foreach my $table (qw/EPG OLDEPG TIMERS CHANNELS CHANNELGROUPS/) {
      my $sth = $self->{dbh}->prepare("delete from $table where vid = ?");
      $sth->execute($id)
          or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    }
}

# ------------------
sub list {
# ------------------
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');

    my %f = (
        'id' => gettext('Service'),
        'active' => gettext('Active'),
        'master' => gettext('Primary'),
        'host' => gettext('Host'),
        'cards' => gettext('Typ of Cards')
    );

    my $sql = qq|
SELECT SQL_CACHE
  id as \'$f{id}\',
  active as \'$f{active}\',
  master as \'$f{master}\',
  host as \'$f{host}\',
  cards as \'$f{cards}\'
from 
  RECORDER
    |;

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute()
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);

    $console->table($erg);
}


sub _gethost {
    my $self = shift  || return error('No object defined!');
    my $vdrid = shift;
    
    unless(exists $self->{Cache}) {
      my $sth = $self->{dbh}->prepare("SELECT * from RECORDER where active = 'y'");
      $sth->execute()
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      $self->{Cache} = $sth->fetchall_hashref('id');
    }

    unless($self->{Cache} && defined $self->{Cache}) {
      panic ("Couldn't query any defined video disk recorder.");
      return undef;
    }

    if($vdrid) {
      unless(defined $self->{Cache}->{$vdrid}) {
        error sprintf("Definition of video disk recorder with id '%s' does not exist in the database.", $vdrid);
        return undef;
      }
      return $self->{Cache}->{$vdrid};
    } else {
      foreach my $id (keys %{$self->{Cache}}) {
        my $h = $self->{Cache}->{$id};
        next unless($h->{master} eq 'y');
        return $h;
      }
    }
    my ($k, $v) = each %{$self->{Cache}};
    debug sprintf("None primary video disk recorder defined in the database, use %s",$v->{host});
    return $v;
}

sub primary_hosts {
    my $self = shift  || return error('No object defined!');
  
    unless($self->{Cache}) {
      return undef unless($self->_gethost());
    }

    foreach my $id (keys %{$self->{Cache}}) {
      my $h = $self->{Cache}->{$id};
      next unless($h->{master} eq 'y');
      return $id;
    }

    my ($k, $v) = each %{$self->{Cache}};
    return $k;
}

sub list_hosts {
    my $self = shift  || return error('No object defined!');
  
    unless($self->{Cache}) {
      return undef unless($self->_gethost());
    }

    my $hosts;
    foreach my $id (keys %{$self->{Cache}}) {
      push(@$hosts,$id);
    }

    return $hosts;
}

sub hostname {
    my $self = shift  || return error('No object defined!');
    my $vdrid = shift;
  
    my $vdr = $self->_gethost($vdrid);
    return $vdr ? $vdr->{host} : undef;
}

sub cards {
    my $self = shift  || return error('No object defined!');
    my $vdrid = shift;
  
    my $vdr = $self->_gethost($vdrid);
    return $vdr ? $vdr->{cards} : undef;
}

sub enum_onlinehosts {
    my $self = shift  || return error('No object defined!');
  
    unless($self->{Cache}) {
      return undef unless($self->_gethost());
      # check online state
      foreach my $vid (keys %{$self->{Cache}}) {
        $self->command('chan',$vid);
      }
    }

    my $hosts;
    foreach my $id (keys %{$self->{Cache}}) {

      next unless($self->{Cache}->{$id}->{online}   
                  && $self->{Cache}->{$id}->{online} eq 'yes');

      push(@$hosts,[$self->{Cache}->{$id}->{host},$id]);
    }

    return $hosts;
}

# ------------------
sub queue_cmds {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $cmd = shift  || 'CALL';
    my $vdrid = shift;

    if($cmd eq 'CALL') {
        my $erg;
        my $result;
        my $queue = delete $self->{Queue};
        $self->{Queue} = undef;
        foreach my $id (keys %$queue) {
          if($id eq 'master') {
            $erg = $self->command($queue->{'master'},undef);
          } else {
            $erg = $self->command($queue->{$id},$id);
          }
          if($erg) {
            if($result) {
              @$result = (@$result, @$erg);
            } else {
              $result = $erg;
            }
          }
        }
        return $result;
    } elsif($cmd eq 'COUNT') {
        my $count = 0;
        foreach my $id (keys %{$self->{Queue}}) {
          next if($vdrid && $id ne $vdrid);
          $count += scalar @{$self->{Queue}->{$id}};
        }
        return $count;
    } else {
        push(@{$self->{Queue}->{$vdrid || 'master'}}, $cmd);
    }
    return undef;
}

# ------------------
sub command {
# ------------------
    my $self = shift || return error('No object defined!');
    my $cmd = shift;
    my $vdrid = shift;

    my $vdr = $self->_gethost($vdrid);
    unless($vdr && defined $vdr->{host} && defined $vdr->{port}) {
      $self->{ERROR} = gettext("None video disk recorder defined in the database.");
      return undef;
    }
    $vdrid = $vdr->{id};

    my $data;
    my $line;
    my @commands = ();
    push(@commands, (ref $cmd eq 'ARRAY' ? @$cmd : $cmd));

    unless(scalar @commands > 0) {
      error ('No Commands!');
      return undef;
    }
    push(@commands, "quit");

    $self->{ERROR} = 0;

    # Put Command follow quit and read Output
    my $telnet = Net::Telnet->new ( Telnetmode => 0,
                                   Timeout    => $self->{timeout},
                                   Errmode    => 'return');

    if(!$telnet or !$telnet->open(Host => $vdr->{host}, Port => $vdr->{port})){
      error sprintf("Couldn't connect to svdrp-socket %s:%s! %s",$vdr->{host},$vdr->{port},$telnet ? $telnet->errmsg : $!);
      $self->{Cache}->{$vdrid}->{online} = 'no';
      return undef;
    }

    # read first line 
    do {
      $line = $telnet->getline;
      chomp($line) if($line);
      if($line) {
        push(@$data, $line);
      }
    } while($line && $line =~ /^\d\d\d\-/);

    unless($data && scalar @$data){
      error sprintf("Couldn't read data from svdrp-socket %s:%s! %s",$vdr->{host},$vdr->{port},$telnet ? $telnet->errmsg : $!);
      $self->{Cache}->{$vdrid}->{online} = 'no';
      return undef;
    }

    main::getVdrVersion($1)
        if($data->[0] =~ /SVDRP\s+VideoDiskRecorder\s+(\d\.\d\.\d+)[\;|\-]/);

    # send commando queue
    foreach my $command (@commands) {
        $telnet->buffer_empty; #clear buffer
        # send command
        if(!$telnet->print($command)) {
          error sprintf("Couldn't send command '%s' to %s:%s! %s",$command,$vdr->{host},$vdr->{port},$telnet ? $telnet->errmsg : $!);
          $self->{Cache}->{$vdrid}->{online} = 'no';
          return undef;      
        }
        # read response
        do {
          $line = $telnet->getline; 
          chomp($line) if($line);
          if($line) {

            if($line =~ /^(\d{3})\s+(.+)/ && (int($1) >= 500)) {
              my $msg = sprintf("Error at command '%s' to %s:%s! %s", $command,$vdr->{host},$vdr->{port}, $2);
              error($msg);
              $self->{ERROR} .= $msg . "\n";
            }

            push(@$data, $line);
          }
        } while($line && $line =~ /^\d\d\d\-/);
    }

    # close socket
    $telnet->close();

    $self->{Cache}->{$vdrid}->{online} = 'yes';

    foreach my $command (@commands) {
      my @lines = (split(/[\r\n]/, $command));
      event(sprintf('Call command "%s" on %s %s.', $lines[0], $vdr->{host}, $self->{ERROR} ? " failed" : "successful")) 
        if($command ne "quit");
    }
    return \@$data;
}

# ------------------
sub status {
# ------------------
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return;

    my $erg = $self->command('stat disk');
    $console->msg($erg, $self->{ERROR})
        if(ref $console);
    return 1 
      unless($self->{ERROR});
    return 0;
}

# ------------------
sub scommand {
# ------------------
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text = shift || return $console->err(gettext("No command defined! Please use scommand 'cmd'."));

    my $erg = $self->command($text);

    return 0
      unless($erg || $self->{ERROR});

    $console->msg($erg, $self->{ERROR});
  
    return 1 
      unless($self->{ERROR});
    return 0;
}

# ------------------
sub err {
# ------------------
    my $self = shift || return error('No object defined!');
    return $self->{ERROR};
}

1;
