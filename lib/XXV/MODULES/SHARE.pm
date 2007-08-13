package XXV::MODULES::SHARE;
use strict;

use Tools;
use Locale::gettext;
use vars qw($AUTOLOAD);


$SIG{CHLD} = 'IGNORE';

# ------------------
sub AUTOLOAD {
# ------------------
    my $obj = shift || return error ('No Object!' );

    my $cmd = (split('::', $AUTOLOAD))[-1];
    return  if($cmd eq 'DESTROY');

    # Den Hash per Hand nachpflegen
    # bis zum nächsten Refresh ...
    if($cmd eq 'setEventLevel' and exists $obj->{EventLevels} and ref $obj->{EventLevels} eq 'HASH') {
        $obj->{EventLevels}->{$_[0]}->{Level} = $_[1];
    }

    if($obj->{SOAP} && $obj->{active} eq 'y') {
        my $erg = $obj->CmdToSoap($obj->{SOAP}, $cmd, $obj->{SessionId}, @_);
        return $erg;
    }
}


# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'SHARE',
        Prereq => {
            'SOAP::Lite' => 'Client and server side SOAP implementation.',
        },
        Description => gettext('This module send and read shared data from SOAP Server.'),
        Version => '0.03',
        Date => '30.06.2006',
        Author => 'xpix',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'n',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            uri => {
                description => gettext('The uri identifies the class on the server. The url (with port) for the XXV-SOAP-Server Address.'),
                default     => 'http://xpix.dyndns.org:81/XXV/Server',
                type        => 'url',
                required    => gettext('This is required!'),
            },
            proxy => {
                description => gettext('The proxy identifies the CGI script that provides access to the class, Is simply the address of the server to contact that provides the methods.'),
                default     => 'http://xpix.dyndns.org:81/',
                type        => 'url',
                required    => gettext('This is required!'),
            },
            interval => {
                description => gettext('How often shared data are to be updated (in seconds).'),
                default     => 3600,
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
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # The Initprocess
    $self->_init or return error('Problem to initialize module');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    $obj->{SessionId} = $obj->generateUniqueId
        unless($obj->{SessionId});

    main::after(sub{

        $obj->{SOAP} = $obj->ConnectToSOAP($obj->{SessionId});

        unless($obj->{SOAP}) {
            error("Can't connect to SOAP server %s!", $obj->{uri});
            return 0;
        } else {
            $obj->getSoapData();
            Event->timer(
              interval => $obj->{interval},
              prio => 6,  # -1 very hard ... 6 very low
              cb => sub{ $obj->getSoapData() },
            );
        }
          return 1;
    }, "SHARE: Connect To SOAP Server ...",4) if($obj->{active} eq 'y');

    return 1;
}

# ------------------
sub getSoapData {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    return unless($obj->{SOAP} and $obj->{active} eq 'y');
    lg 'Start interval share to get for Levels!';
    $obj->{EventLevels} = $obj->getEventLevels();
    lg 'Start interval share to get for TopTen!';
    $obj->{TopTen} = $obj->getTopTen(1000);
}


# ------------------
sub generateUniqueId {
# ------------------
    my $obj = shift  || return error ('No Object!' );

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
sub ConnectToSOAP {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $sid = shift  || $obj->{SessionId} || return error ('No SesionID!' );
    my $uri = shift  || $obj->{uri};
    my $prx = shift  || $obj->{proxy};

    return undef
        if($obj->{active} ne 'y');
    
    my $soap = SOAP::Lite
		->uri($uri)
		->proxy($prx, timeout => 5)
		->on_fault(sub{});

    my $usrkey;
    if($soap) {
      $usrkey = $obj->CmdToSoap($soap,'getUsrKey',$obj->{SessionId}) or error "Can't get user key";
      error "Response contain wrong answer" if($usrkey ne $obj->{SessionId});
    }

    return $soap
       if($usrkey eq $obj->{SessionId});
   
    return undef;
}

# ------------------
sub getEventLevel {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $eid = shift  || return;

    return unless($obj->{EventLevels});

    return $obj->{EventLevels}->{$eid}->{Level}
        if(exists $obj->{EventLevels}->{$eid});
}

# ------------------
sub TopTen {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $anzahl = shift || 10;

    $obj->{TopTen} = $obj->getTopTen(1000) 
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
        timers => $tim->getEpgIds
       });
}

# ------------------
sub CmdToSoap {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $soap = shift  || return error ('No SOAP!' );
    my $cmd = shift  || return error ('No Command!' );
    my @arg = @_;

    lg(sprintf("CmdToSoap : %s - %s",$cmd, join(", ",@arg)));

    $obj->{CAN}->{$cmd} = $soap->can($cmd)
        unless(exists $obj->{CAN}->{$cmd});

    my $res = eval "\$soap->$cmd(\@arg)";
    $@ ? return error('SyntaxError: $@') :
        defined($res) && $res->fault ?
            return error('Fault %s-%s', $res->faultcode, $res->faultstring) :
                !$soap->transport->is_success ?
                    return error('Transport Error: %s', $soap->transport->status) :
                        return $res->result;
}

1;
