package XXV::MODULES::REPORT;

use strict;

use Tools;


# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'REPORT',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module read in every module the status information and display this. Also this module send this informations e.g. as mail report.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Level => 'user',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = shift;
                    if($value eq 'y') {
                      my $module = main::getModule('EVENTS');
                      if(!$module or $module->{active} ne 'y') {
                        return undef, sprintf(gettext("Module can't activated! This module depends module %s."),'EVENTS');
                      }
                    }
                    return $value;
                },
            },
            interval => {
                description => gettext('Time in hours to send the report.'),
                default     => 6,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            host => {
                description => gettext('Used host of referred link inside reports.'),
                default     => main::getModule('STATUS')->name,
                type        => 'host',
            },
        },
        Commands => {
            report => {
                description => gettext("Display the report screen 'modname'"),
                short       => 'rp',
                callback    => sub{ $obj->report(@_) },
            },
            request => {
                description => gettext("Display the actual news site 'typ'"),
                short       => 'req',
                callback    => sub{ $obj->request(@_) },
                binary      => 'nocache'
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

    # the big Config
    $self->{CONFIG} = $attr{'-config'};

    # the dbh handle
    $self->{dbh} = delete $attr{'-dbh'};

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

    $self->{LastReportTime} = time;

    # Interval to send report
    Event->timer(
        interval => $self->{interval}*3600,
        prio => 6,  # -1 very hard ... 6 very low
        cb => sub{
            $self->report();
            $self->{LastReportTime} = time;
        },
    );

    # The Initprocess
    my $erg = $self->init or return error('Problem to initialize module!');

    # Initiat after load modules ...
    main::after( sub{
        my $start = main::getStartTime;
        $self->news(
            sprintf(gettext('XXVD System %s started'), main::getVersion),
            sprintf(gettext('Start time: %s'), datum($start)),
            undef,
            undef,
            'important'
        );
        return 1;
    }, "Send start message to news modules ...");

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift  || return error('No object defined!');

    # Load the NEWS Plugins ...
    my @mods = glob($obj->{paths}->{NEWSMODS}.'/*.pm');

    # Try to use the news plugins
    foreach my $module (reverse @mods) {
        my $moduleName = 'XXV::OUTPUT::NEWS::'.(split('\.',(split('/', $module))[-1]))[0];

        # make an object for the module
	    eval "use $moduleName";
        error $@ if $@;
        my $mod = $moduleName->new(
            -config => $obj->{CONFIG},
            -dbh    => $obj->{dbh},
            -paths  => $obj->{paths},
            -host  => $obj->{host},
        );

        unless($mod) {
            error sprintf('Load news module %s failed!',$moduleName);
            next;
        }

        $obj->{NEWSMODS}->{$moduleName} = $mod;

        main::addModule($moduleName, $obj->{NEWSMODS}->{$moduleName});

        debug sprintf("Load news module %s(%s)\n",
            $moduleName,
            (ref $obj->{NEWSMODS}->{$moduleName})
                ? $obj->{NEWSMODS}->{$moduleName}->{MOD}->{Version}
                : 'failed!');
    }

    return 1;
}


# ------------------
sub report {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $modulename = shift || '';

    my $mods = main::getModules();
    my $cfg = main::getModule('CONFIG')->{config};

    # Look for status entry in modCfg and call his
    my $result = {};
    foreach my $modName (sort keys %{$mods}) {
        my $modCfg = $mods->{$modName}->{MOD};
        next if($modulename and uc($modulename) ne $modCfg->{Name});
        next if(exists $mods->{$modName}->{active} and $cfg->{$modCfg->{Name}}->{active} eq 'n');
        if(exists $modCfg->{Status} and ref $modCfg->{Status} eq 'CODE') {
            $result->{$modCfg->{Name}} = $modCfg->{Status}($watcher, $console, $obj->{LastReportTime});
        }
    }

    $console->table($result, {hide_HeadLine => 1, hide_HeadRow => 1, maxwidth => 80})
        if(ref $console);

    return 1;
}

# ------------------
sub news {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $title = shift || return error('No title defined!');
    my $text  = shift || '';
    my $cmd   = shift || '';
    my $id    = shift || '';
    my $levname  = shift || 'harmless'; # Level for how important is this news?

    # convert Levelname to integer
    my $lev   = $obj->scala($levname)
        || return error('Problem to analyze level!');

    my $hmod = main::getModule('HTTPD') or return;

    my  $url = sprintf("http://%s:%s/", $obj->{host}, $hmod->{Port});
        $url = sprintf("%s?cmd=%s&data=%s", $url, $cmd, $id)
            if($cmd && $id);

    my $news = {
        AddDate => time,
        Title   => $title,
        Text    => $text,
        Cmd     => $cmd,
        Id      => $id,
        Url     => $url,
        Level   => $lev,
        LevelName => $levname,
        category => $obj->translate_level($levname)
    };

    # Send to all activated News modules
    foreach my $modName (sort keys %{$obj->{NEWSMODS}}) {

        # Active?
        next if($obj->{NEWSMODS}->{$modName}->{active} ne 'y');

        # Level correct?
        next if(exists $obj->{NEWSMODS}->{$modName}->{level}
                and $obj->{NEWSMODS}->{$modName}->{level} >= $lev);

        # Do to send (first read and then send)
        $obj->{NEWSMODS}->{$modName}->read($news);
    }

}

# ------------------
sub request {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    # To this time you can set on
    # cmd=request&data=rss&ver=2 or
    # cmd=request&data=mail
    # ...
    my $typ = shift || return $console->err(gettext("Sorry, but none type requested!"));
    my $params = shift || {};

    my ($mod) = grep(/${typ}$/i, keys %{$obj->{NEWSMODS}});

    return $console->err(sprintf(gettext("Sorry, but this type '%s' does not exist on this system!"), $typ))
        unless($mod);

    return $console->err(gettext("Sorry, but this module is not active!"))
        unless($obj->{NEWSMODS}->{$mod}->{active} eq 'y');

    return $console->out(
        $obj->{NEWSMODS}->{$mod}->req($params),
        $obj->{NEWSMODS}->{$mod}->{TYP}
    );
}


# ------------------
sub scala {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $typ = shift  || return 10;

    $obj->{SCALA} = {
        'all'           => 1,
        'harmless'      => 10,
        'interesting'    => 30,
        'veryinteresting'=> 50,
        'important'     => 70,
        'veryimportant' => 100,
        'none'          => 200, 
    } unless(exists $obj->{SCALA});

    if($typ and exists $obj->{SCALA}->{$typ}) {
        return $obj->{SCALA}->{$typ};
    } else {
        return error sprintf("Level %s does not exist! Please use %s", $typ, join(',', keys %{$obj->{SCALA}}));
    }
}

# ------------------
sub get_level_as_array {
# ------------------
    my $obj = shift || return error('No object defined!');

    return [
            [ 1, gettext('All messages') ],        # Include all messages, dont use as category
            [ 10, gettext('Harmless') ],
            [ 30, gettext('Interesting') ],
            [ 50, gettext('Very interesting') ],
            [ 70, gettext('Important') ],
            [ 100, gettext('Very important') ],
            [ 200, gettext('None messages') ]      # Exclude all messages, dont use as category
          ];
}

sub translate_level {
    my $obj = shift  || return error('No object defined!');
    my $level = shift  || 'harmless';

    my $s = $obj->scala($level);

    my $erg = $obj->get_level_as_array();
    foreach my $w ( @$erg ) {
        return $w->[1] if($s <= $w->[0]);
    }
    return gettext('Harmless');
}

1;
