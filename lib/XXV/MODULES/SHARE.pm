package XXV::MODULES::SHARE;
use strict;

use Tools;
use Locale::gettext;
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
    if($cmd eq 'setEventLevel' and exists $obj->{EventLevels} and ref $obj->{EventLevels} eq 'HASH') {
        $obj->{EventLevels}->{$_[0]}->{Level} = $_[1];
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
                        return undef, sprintf(gettext("Modul can't activated! This modul depends modul %s."),'EVENTS');
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
    lg 'Start interval to get popularity levels!';
    my $levels = $obj->getEventLevels();
    my $eventlevels;
    foreach my $event (@$levels) {
      my $id = $event->{e}; # eventid
      $eventlevels->{$id} = {
        'Eventid' => $id,
        'Level' => $event->{l} #level
      }
    }
    $obj->{EventLevels} = $eventlevels;
#dumper($eventlevels);

    lg 'Start interval to get popularity top ten events!';
    my $topevents = $obj->getTopTen(1000);
    my $topten;
    foreach my $top (@$topevents) {
      push(@$topten, [
        $top->{e}, # eventid
        $top->{l}, # level
        $top->{c}, # count
        $top->{r}  # rank
        ]
      );
    }
#dumper($topten);
    $obj->{TopTen} = $topten;
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

    return unless($obj->{EventLevels});

    return $obj->{EventLevels}->{$eid}->{Level}
        if(exists $obj->{EventLevels}->{$eid});
}

# ------------------
sub TopTen {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $anzahl = shift || 10;

    $obj->getSoapData()
      unless($obj->{TopTen});

    my $data = $obj->{TopTen};

    my $epg = main::getModule('EPG');
    my $tim = main::getModule('TIMERS');
    my $can = main::getModule('CHANNELS');

    my @fields = ('eventid','title','subtitle','description','channel_id','starttime','video','audio');
    my @query = @fields;

       @query = ('eventid','title','subtitle','description','channel_id','UNIX_TIMESTAMP(starttime) as starttime','video','audio')
          if($console->typ eq 'HTML');


    my $out = [];
    foreach my $entry (@$data) {
            my $edata = $epg->getId( $entry->[0], join(", ", @query) );
            next unless(keys %$edata);
            push(@$out, [ @fields, 'Rank', '__Level', '__Count' ])
                unless(scalar @$out);
            my @val = map { $edata->{$_} } @fields;
            push(@$out, [ @val, $entry->[3], $entry->[1],$entry->[2] ]);
            last if(scalar @$out > $anzahl);
        }

    return $console->table($out, {
        channels => $can->ChannelHash('Id'),
        timers => $tim->getEvents()
       });
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
