package XXV::MODULES::SHARE;
use strict;

use Tools;
use vars qw($AUTOLOAD);


$SIG{CHLD} = 'IGNORE';

# ------------------
sub AUTOLOAD {
# ------------------
    my $obj = shift || return error('No object defined!');

    my $cmd = (split('::', $AUTOLOAD))[-1];
    return  if($cmd eq 'DESTROY');

    # Den Hash per Hand nachpflegen
    # bis zum nächsten Refresh ...
    if($cmd eq 'setEventLevel') {
        $obj->StoreEventLevel($_[0],$_[1]);
        $_[2] += $obj->{TimeOffset} if(exists $obj->{TimeOffset});
    }

    if($obj->{SOAP} && $obj->{active} eq 'y') {
        my $erg = $obj->CmdToService($obj->{SOAP}, $cmd, $obj->{SessionId}, @_);
        return $erg;
    }
}


# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'SHARE',
        Prereq => {
            'SOAP::Lite' => 'Client and server side SOAP implementation.',
        },
        Description => gettext('This module send and read shared data from SOAP Server.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'n',
                type        => 'confirm',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = shift;
                    if($value eq 'y') {
                      my $module = main::getModule('EVENTS');
                      unless($module or $module->{active} eq 'y') {
                        return undef, sprintf(gettext("Module can't activated! This module depends module %s."),'EVENTS');
                      }
                    }
                    return $value;
                },

            },
            rating => {
                description => gettext('URL to access popularity web service.'),
                default     => 'http://www.deltab.de/t10.php?wsdl',
                type        => 'string',
                required    => gettext('This is required!'),
            },
            update => {
                description => gettext('How often shared data are to be updated (in hours).'),
                default     => 24,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            topten => {
                description => gettext("Display the TopTen list of timers."),
                short       => 't10',
                callback    => sub{ $obj->TopTen(@_) },
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

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # all configvalues to $self without parents (important for ConfigModule)
    map {
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_};
        $self->{$_} = $self->{MOD}->{Preferences}->{$_}->{default} unless($self->{$_});
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # The Initprocess
    $self->_init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error('No object defined!');

    $obj->{SessionId} = $obj->generateUniqueId
        unless($obj->{SessionId});

    my $version = 27; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows

    # remove old table, if updated version
    if(!tableUpdated($obj->{dbh},'SHARE',$version,1)) {
      return 0;
    }

    $obj->{dbh}->do(qq|
        CREATE TABLE IF NOT EXISTS SHARE (
            eventid int unsigned default '0',
            level float,
            quantity int unsigned default '0',
            rank float,
            addtime datetime NOT NULL default '0000-00-00 00:00:00',
            PRIMARY KEY (eventid)
          ) COMMENT = '$version'
      |);

    main::after(sub{

        $obj->{SOAP} = $obj->ConnectToService($obj->{SessionId},$obj->{rating});

        unless($obj->{SOAP}) {
            error sprintf("Couldn't connect to popularity web service %s!", $obj->{rating});
            return 0;
        } else {
            my $servertime = $obj->getServerTime();
            if($servertime) {
              my $offset = time - $servertime;
              if($offset > 60 || $offset < -60) {
                $obj->{TimeOffset} = $offset;
                lg sprintf('Popularity web service has time offset %d seconds.',$offset);
              }
            }
        }
        return 1;
    }, "SHARE: Connect to popularity web service ...",4) if($obj->{active} eq 'y');

    main::after(sub{
        if($obj->{SOAP}) {
            $obj->getSoapData();
            Event->timer(
              interval => $obj->{update} * 3600,
              prio => 6,  # -1 very hard ... 6 very low
              cb => sub{ 
                $obj->getSoapData() 
              },
            );
        }
          return 1;
    }, "SHARE: Update data with popularity web service ...",48) if($obj->{active} eq 'y');

    return 1;
}

# ------------------
sub getSoapData {
# ------------------
    my $obj = shift  || return error('No object defined!');
    return unless($obj->{SOAP} and $obj->{active} eq 'y');

    lg 'Start interval to get popularity top ten events!';
    my $topevents = $obj->getTopTen(1000);
    my $time = time;
    foreach my $t (@$topevents) {
      my $sth = $obj->{dbh}->prepare('REPLACE INTO SHARE(eventid, level, quantity, rank, addtime) VALUES (?,?,?,?,FROM_UNIXTIME(?))');
      $sth->execute(
        $t->{e}, # eventid
        $t->{l}, # level
        $t->{c}, # count
        $t->{r}, # rank
        $time
      );
    }

    my $dsth = $obj->{dbh}->prepare('DELETE FROM SHARE WHERE addtime != FROM_UNIXTIME(?)');
    $dsth->execute($time);
}


# ------------------
sub generateUniqueId {
# ------------------
    my $obj = shift  || return error('No object defined!');

    my $sessionId;
    for(my $i=0 ; $i< 16 ;)
    {
    	my $j = chr(int(rand(127)));

    	if($j =~ /[a-zA-Z0-9]/)
    	{
    		$sessionId .=$j;
    		$i++;
    	}
    }
    return $sessionId;
}

# ------------------
sub ConnectToService {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $sid = shift  || $obj->{SessionId} || return error('No session id defined!');
    my $service = shift;

    return undef
        if($obj->{active} ne 'y');

    my $version = main::getVersion();

    my $client = SOAP::Lite->new;
    if($client->can('schema')) {
     my $schema = $client->schema;
     if($schema && $schema->can('useragent')) {
       my $ua = $schema->useragent;
       $ua->agent(sprintf("xxv %s",$version)) if($ua);
      }
    }
    my $webservice = $client->service($service);
      
    my $usrkey;
    if($webservice) {
      $usrkey = $obj->CmdToService($webservice,'getUsrKey',$obj->{SessionId}) 
        or error "Couldn't get user key";
      error "Response contain wrong answer" if($usrkey ne $obj->{SessionId});
    }

    return $webservice
       if($usrkey eq $obj->{SessionId});
   
    return undef;
}

# ------------------
sub getEventLevel {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eid = shift  || return;

    my $sql = qq|
SELECT SQL_CACHE 
    level from SHARE
where
    eventid = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eid)
        or return error(sprintf("Event '%s' does not exist in the database!",$eid));
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{level} : 0;
}

# ------------------
sub StoreEventLevel {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eid = shift  || return;
    my $level = shift  || return;

    my $sth = $obj->{dbh}->prepare('REPLACE INTO SHARE(eventid, level, quantity, rank, addtime) VALUES (?,?,1,1,NOW())');
    $sth->execute(
      $eid, # eventid
      $level # level
    );
}

# ------------------
sub TopTen {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $anzahl = shift || 10;

    my %f = (
        'id' => gettext('Service'),
        'title' => gettext('Title'),
        'channel' => gettext('Channel'),
        'start' => gettext('Start'),
        'stop' => gettext('Stop'),
        'day' => gettext('Day'),
        'rank' => gettext('Rank')
    );

    my $sql = qq|
    SELECT SQL_CACHE 
        e.eventid as \'$f{'id'}\',
        e.title as \'$f{'title'}\',
        e.subtitle as __Subtitle,
        c.Name as \'$f{'channel'}\',
        c.POS as __Pos,
        DATE_FORMAT(e.starttime, '%H:%i') as \'$f{'start'}\',
        DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(e.starttime) + e.duration), '%H:%i') as \'$f{'stop'}\',
        UNIX_TIMESTAMP(e.starttime) as \'$f{'day'}\',
        e.description as __description,
        IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,
        ( SELECT 
            t.id
            FROM TIMERS as t
            WHERE t.eventid = e.eventid
            LIMIT 1) as __timerid,
        ( SELECT 
            (t.flags & 1) 
            FROM TIMERS as t
            WHERE t.eventid = e.eventid
            LIMIT 1) as __timeractiv,
        ( SELECT 
            NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
            FROM TIMERS as t
            WHERE t.eventid = e.eventid
            LIMIT 1) as __running,
        e.video as __video,
        e.audio as __audio,
        s.rank as \'$f{'rank'}\',
        s.level as __level,
        s.quantity as __quantity
    from
        EPG as e,
        CHANNELS as c,
        SHARE as s
    where
        e.eventid = s.eventid
        AND e.channel_id = c.Id
        AND ((UNIX_TIMESTAMP(e.starttime) + e.duration) > UNIX_TIMESTAMP())
    order by
        rank desc
    LIMIT ?
        |;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($anzahl)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    map {
        $_->[7] = datum($_->[7],'weekday');
    } @$erg;
    unshift(@$erg, $fields);

    return $console->table($erg);
}

# ------------------
sub CmdToService {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $service = shift  || return error('No service defined!');
    my $cmd = shift  || return error('No command defined!');
    my @arg = @_;

    lg(sprintf("CmdToService : %s - %s",$cmd, join(", ",@arg)));

    my $res = eval "\$service->$cmd(\@arg)";
    $@ ? return error('SyntaxError: $@') 
       : return $res;
}

1;
