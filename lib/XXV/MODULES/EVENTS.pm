package XXV::MODULES::EVENTS;
use strict;

use Tools;


# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'EVENTS',
        Prereq => {
            'Date::Manip'  => 'date manipulation routines',
        },
        Description => gettext(
"This module manage the events for control and watch the xxv system.
An additional Loghandler is installed and parse every Message. If
a defined Event exists and match the keywords defined in
Module->RegEvent->SearchForEvent then call the Loghandler 'callEvent'.
This sub look in Module->RegEvent->Actions, and call this Routines.
"),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
#            list => {
#                description => gettext('Display the event list'),
#                short       => 'el',
#                callback    => sub{ $obj->list(@_) },
#                Level       => 'user',
#            },
#            eedit => {
#                description => gettext('Edit a event'),
#                short       => 'ee',
#                callback    => sub{ $obj->edit(@_) },
#                Level       => 'user',
#            },
#            etoogle => {
#                description => gettext('Change a event on or off'),
#                short       => 'eto',
#                callback    => sub{ $obj->toogle(@_) },
#                Level       => 'user',
#            },
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

    $self->{Trenner} = "\n#-- NextSub --#\n";

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

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error('No object defined!');

    main::after(sub{
        $obj->{EVENTS} = $obj->searchForEvents();
        # This will add a callback for log events (ignore verbose)
        $Tools::LOGCALLB = sub{
            $obj->callEvent(@_);
        };
        return 1;
    }, "EVENTS: Look for event entrys in modules ...", 3);

    return 1;
}

# ------------------
sub searchForEvents {
# ------------------
    my $obj = shift || return error('No object defined!');

    my $mods = main::getModules();
    my $events = {};
    foreach my $modname (keys %$mods) {
        if(exists $mods->{$modname}->{MOD}->{RegEvent}
            and my $re = $mods->{$modname}->{MOD}->{RegEvent}
        ) {
            foreach my $rname (keys %$re) {
                my $options = $re->{$rname};
                $options->{Grp} = (split(/::/, $modname))[-1];
                $events->{$rname} = $options;
            }
        }
    }
    return $events;
}

# ------------------
sub callEvent {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        'Mod' => shift,
        'Sub' => shift,
        'Msg' => shift,
    };
    return unless(exists $obj->{EVENTS});
    return if($obj->{active} ne 'y');

    foreach my $id (keys %{$obj->{EVENTS}}) {
        my $entry = $obj->{EVENTS}->{$id};
        my $bool = 0;

        # Search for right fields
        next unless(exists $entry->{SearchForEvent});
        for my $sType (keys %{$entry->{SearchForEvent}}) {
            my $sValue = $entry->{SearchForEvent}->{$sType};
            $bool++ if(index($args->{$sType}, $sValue) > -1);
        }
        next unless($bool >= scalar keys %{$entry->{SearchForEvent}});

        # Search for Matchtext
        my $MatchVar = {};
        if(exists $entry->{Match}) {
            $bool = 0;
            for my $mName (keys %{$entry->{Match}}) {
                my $mRegex = $entry->{Match}->{$mName};
                $MatchVar->{$mName} = $1
                    if($args->{Msg} =~ $mRegex);
                $bool = 1 if($MatchVar->{$mName});
            }
            next unless($bool);
        }

        # Call the Actions
        if(exists $entry->{Actions}) {
            for my $action (@{$entry->{Actions}}) {
                my $callback;
                my $code = sprintf('$callback = %s;', $action);
                eval($code);
                if($@) {
                    error($@);
                    next;
                }
                my $erg = &$callback($MatchVar, $entry)
                    if(ref $callback eq 'CODE');
            }
        }
    }

    return 1;
}
1;
