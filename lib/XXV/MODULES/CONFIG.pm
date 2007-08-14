package XXV::MODULES::CONFIG;

use strict;

use Tools;
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'CONFIG',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module edit, write and reconfigure the configuration.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Level       => 'admin',
        Commands => {
            configedit => {
                description => gettext("Edit configuration 'sector'"),
                short       => 'ce',
                callback    => sub{ $obj->edit(@_) },
            },
            configwrite => {
                description => gettext('Write configuration'),
                short       => 'cw',
                callback    => sub{ $obj->write(@_) },
            },
            configget => {
                description => gettext("Get configuration from 'modname'"),
                short       => 'cg',
                callback    => sub{ $obj->get(@_) },
            },
            reconfigure => {
                description => gettext('Reconfigure all Processes'),
                short       => 'cr',
                callback    => sub{ $obj->reconfigure(@_) },
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

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # read the Configdata
    $self->{config} = $attr{'-config'};

	return $self;
}

# ------------------
sub menu {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $sector  = shift || 0;

    my $ret = {};
    $ret->{title} = gettext("Preferences for XXV");
    $ret->{highlight} = $sector;

    my $mods = main::getModules;
    foreach my $module (sort keys %{$mods}) {
        my $name = $mods->{$module}->{MOD}->{Name};
        next unless(exists $obj->{config}->{$name});

        $ret->{links}->{$name} = {
                text => $name,
                link => "?cmd=configedit&data=$name",
        };
    }
    $ret->{links}->{'reconfigure'} = {
            text => gettext("Reconfigure"),
            link => "?cmd=reconfigure",
    };
    $ret->{links}->{'write'} = {
            text => gettext("Write configuration"),
            link => "?cmd=configwrite",
    };

    return $console->littlemenu($ret);
}

# ------------------
sub edit {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $sector  = shift || 0;
    my $data    = shift || 0;

    $obj->menu( $watcher, $console, $sector )
        if($console->{TYP} eq 'HTML' or ($console->{TYP} ne 'HTML' and not $sector));
    return unless $sector;

    $sector = uc($sector) unless($sector eq 'General');

    my $cfg = $obj->{config}->{$sector}
        or return $console->err(sprintf(gettext("Sorry, but the section %s does not exist in configuration!"),$sector));

    my $mod = main::getModule($sector);

    my $prefs = $mod->{MOD}->{Preferences}
        or return $console->err(sprintf(gettext("Sorry, but the 'Preferences' in Module: %s do not exist"),$sector));

    my $questions = [];
    foreach my $name (sort { lc($a) cmp lc($b) } keys(%{$prefs})) {
        my $def = $prefs->{$name}->{default};
        $def = $cfg->{$name}
            if(defined $cfg->{$name} && $cfg->{$name} ne "");
        push(@$questions, $name,
            {
                typ => $prefs->{$name}->{type} || 'string',
                options => $prefs->{$name}->{options},
                msg => sprintf("%s:\n%s", ucfirst($name), ($prefs->{$name}->{description} || gettext('No Description'))),
                def => $def,
                req => $prefs->{$name}->{required},
                choices  => $prefs->{$name}->{choices},
                check  => $prefs->{$name}->{check},
                readonly  => $prefs->{$name}->{readonly} || 0,
            }
        );
    }

    $console->link({text => sprintf(gettext('%s manual'), $sector), url => "?cmd=doc&data=$sector"})
        if($console->typ eq 'HTML');

    $cfg = $console->question(sprintf(gettext('Change %s configuration'), $sector), $questions, $data);

    if(ref $cfg eq 'HASH') {
        $obj->{config}->{$sector} = $cfg;
        $obj->reconfigure();
        $obj->write();

        debug sprintf('Config Section "%s" is changed and saved%s',
            $sector,
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $console->message(sprintf(gettext("Sector: '%s' save .. please wait."), $sector));
        $console->redirect({url => $console->{browser}->{Referer}, wait => 2})
            if($console->typ eq 'HTML');
    }
}

# ------------------
sub write {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;

    $obj->reconfigure($watcher, $console);
    my $configfile = main::getUsrConfigFile;

    $obj->{config}->write( $configfile )
        or return error( sprintf ("Can't written '%s': %s", $configfile , $! ));
    $console->message(sprintf gettext("Configuration written in '%s'."), $configfile)
        if(ref $console);

    $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
        if(ref $console and $console->typ eq 'HTML');
}

# ------------------
sub get {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $modname = shift || 0;

    return $console->err(gettext('I need a name of the module, in order to indicate the configuration!'))
        unless($modname and ref $console);

    $modname = uc($modname) unless($modname eq 'General');

    my $cfg = $obj->{config}->{$modname};

    $console->err(sprintf(gettext("Sorry, but the section %s does not exist in configuration!"),$modname))
        if(! $cfg and ref $console);

    if(ref $console) {
        return $console->table($cfg);
    } else {
        return $cfg;
    }
}

# ------------------
sub reconfigure {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;

    my $cfg = $obj->{config};
    foreach my $moduleName (keys %$cfg) {
        if($moduleName eq 'General') {
            main::reconfigure();
        } else {
            my $mod = main::getModule($moduleName)
                or (error("$moduleName does not exist!") && next);
            foreach my $parameter (keys %{$mod->{MOD}->{Preferences}}) {
                if(defined $mod->{$parameter}) {
                    $cfg->{$moduleName}->{$parameter} = $mod->{MOD}->{Preferences}->{$parameter}->{default}
						if(not defined $cfg->{$moduleName}->{$parameter});
                    $mod->{$parameter} = $cfg->{$moduleName}->{$parameter};

                    # Check this input
                    if(my $check = $mod->{MOD}->{Preferences}->{$parameter}->{check}) {
                        if(ref $check eq 'CODE') {
                            my ($ok, $err) = &$check($mod->{$parameter});
                            unless($ok || not $err) {
                                my $message = sprintf("Config -> %s -> %s: %s %s", $moduleName, $parameter, $mod->{$parameter}, $err);
                                if(ref $console) {
                                    $console->err($message);
                                } else {
                                    error $message;
                                }
                            }
                        }
                    }

                } else {
                    $console->err(sprintf(gettext("Strange, i can not find %s in %s"), $parameter, $moduleName))
                        if(ref $console);
                }
            }
        }
    }

    $obj->menu( $watcher, $console )
        if(ref $console and $console->{TYP} eq 'HTML');
    $console->message(gettext('Reconfigure successfully'))
        if(ref $console);
}

# ------------------
sub realModNames {
# ------------------
    my $obj = shift  || return error ('No Object!' );

    my $mods = main::getModules();
    my @realModName;

    # Search for command and display the Description
    foreach my $modName (sort keys %{$mods}) {
        my $modCfg = $mods->{$modName}->{MOD};
        push(@realModName, $mods->{$modName}->{MOD}->{Name})
          if(exists $mods->{$modName}->{MOD}->{Name});
    }

    return sort @realModName;
}


1;
