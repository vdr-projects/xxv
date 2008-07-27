package XXV::MODULES::CONFIG;

use strict;

use Tools;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'CONFIG',
        Prereq => {
            'Module::Reload'    => 'Reload %INC files when updated on disk ',
        },
        Description => gettext('This module edits, writes and saves the configuration.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Commands => {
            configedit => {
                description => gettext("Edit configuration 'section'"),
                short       => 'ce',
                callback    => sub{ $obj->edit(@_) },
                Level       => 'admin',
            },
            configwrite => {
                description => gettext('Saves the configuration.'),
                short       => 'cw',
                callback    => sub{ $obj->write(@_) },
                Level       => 'admin',
            },
            configget => {
                description => gettext("Get configuration from 'modname'"),
                short       => 'cg',
                callback    => sub{ $obj->get(@_) },
                Level       => 'admin',
            },
            reconfigure => {
                description => gettext('Edit all processes'),
                short       => 'cr',
                callback    => sub{ $obj->reconfigure(@_) },
                Level       => 'admin',
            },
            help => {
                description => gettext("This will display all commands or description of module 'name'."),
                short       => 'h',
                callback    => sub{
                    return $obj->usage(@_);
                },
            },
            reload => {
                description => gettext("Restart all modules."),
                short       => 'rel',
                callback    => sub{
                    my ($w, $c, $l) = @_;
                    $Module::Reload::Debug = CORE::int(($Tools::VERBOSE+.5)/2);
#                   my %Status = %Module::Reload->Stat;
                    my $cnt = Module::Reload->check();
#                   my $files;
#                   foreach my $file (keys %Module::Reload::Stat) {
#                     push(@$files, $file) 
#                       if($Module::Reload::Stat{$file} ne $Status{$file});
#                   }
                    if($cnt) {
                      $c->message(sprintf(gettext("Reload %d modules."),$cnt));
                    } else {
                      $c->message(gettext("There none module reloaded."));
                    }
                },
                Level   => 'admin'
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

    # Try to use the Requirments
    map {
        eval "use $_";
        if($@) {
          my $m = (split(/ /, $_))[0];
          return panic("\nCouldn't load perl module: $m\nPlease install this module on your system:\nperl -MCPAN -e 'install $m'");
        }
    } keys %{$self->{MOD}->{Prereq}};

    # read the Configdata
    $self->{config} = $attr{'-config'};

	return $self;
}

# ------------------
sub menu {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $sector  = shift || 0;

    my $ret = {};
    $ret->{title} = gettext("Settings for XXV");
    $ret->{highlight} = $sector;

    my $mods = main::getModules;
    foreach my $module (sort keys %{$mods}) {
        my $name = $mods->{$module}->{MOD}->{Name};
        error(sprintf("Missing real modul name %s",$module)) unless($name);
        next unless($name && exists $obj->{config}->{$name});

        $ret->{links}->{$name} = {
                text => $name,
                link => "?cmd=configedit&data=$name",
        };
    }
    $ret->{links}->{'reconfigure'} = {
            text => gettext("Save configuration"),
            link => "?cmd=reconfigure",
    };
    $ret->{links}->{'write'} = {
            text => gettext("Saves the configuration."),
            link => "?cmd=configwrite",
    };

    return $console->littlemenu($ret);
}

# ------------------
sub edit {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $sector  = shift || 0;
    my $data    = shift || 0;

    $obj->menu( $watcher, $console, $sector )
        if($console->{TYP} eq 'HTML' or ($console->{TYP} ne 'HTML' and not $sector));
    return unless $sector;

    $sector = uc($sector) unless($sector eq 'General');

    my $cfg = $obj->{config}->{$sector}
        or return con_err($console, sprintf(gettext("Sorry, but section %s does not exist in the configuration!"),$sector));

    my $mod = main::getModule($sector);

    my $prefs = $mod->{MOD}->{Preferences}
        or return con_err($console, sprintf(gettext("Sorry, but the settings in module: %s do not exist!"),$sector));

    my $questions = [];
    foreach my $name (sort { lc($a) cmp lc($b) } keys(%{$prefs})) {
        my $def = $prefs->{$name}->{default};
        $def = $cfg->{$name}
            if(defined $cfg->{$name} && $cfg->{$name} ne "");
        push(@$questions, $name,
            {
                typ => $prefs->{$name}->{type} || 'string',
                options => $prefs->{$name}->{options},
                msg => sprintf("%s:\n%s", ucfirst($name), ($prefs->{$name}->{description} || gettext('No description'))),
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

    $cfg = $console->question(sprintf(gettext('Edit configuration %s'), $sector), $questions, $data);

    if(ref $cfg eq 'HASH') {
        $obj->{config}->{$sector} = $cfg;
        $obj->reconfigure();
        $obj->write();

        con_msg($console, sprintf(gettext("Section: '%s' saving ... please wait."), $sector));
        $console->redirect({url => sprintf('?cmd=configedit&amp;data=%s',$sector), wait => 1})
            if($console->typ eq 'HTML');
    }
}

# ------------------
sub write {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    $obj->reconfigure($watcher, $console);
    my $configfile = main::getUsrConfigFile;

    $obj->{config}->write( $configfile )
        or return con_err($console, sprintf ("Couldn't write '%s': %s", $configfile , $! ));
    con_msg($console, sprintf(gettext("Configuration written to '%s'."), $configfile));

    $console->redirect({url => '?cmd=configedit', wait => 2})
        if(ref $console and $console->typ eq 'HTML');
}

# ------------------
sub get {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $modname = shift || 0;

    return con_err($console, gettext('Need a name of the module to display the configuration!'))
        unless($modname);

    $modname = uc($modname) unless($modname eq 'General');

    my $cfg = $obj->{config}->{$modname};

    con_err($console, sprintf(gettext("Sorry, but section %s does not exist in the configuration!"),$modname))
        if(! $cfg);

    if(ref $console) {
        return $console->table($cfg);
    } else {
        return $cfg;
    }
}

# ------------------
sub reconfigure {
# ------------------
    my $obj = shift || return error('No object defined!');
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
                              con_err($console, $message);
                            }
                        }
                    }

                } else {
                    con_err($console, sprintf(gettext("Couldn't find %s in %s!"), $parameter, $moduleName));
                }
            }
        }
    }

    $obj->menu( $watcher, $console )
        if(ref $console and $console->{TYP} eq 'HTML');
    con_msg($console, gettext('Edit successful!'));
}

# ------------------
sub realModNames {
# ------------------
    my $obj = shift  || return error('No object defined!');

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

# ------------------
sub usage {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $modulename = shift || 0;
    my $hint = shift || '';
    my $user = shift || $console->{USER};

    my $u = main::getModule('USER');
    unless($user) {
        my $loginObj = $obj;
        $loginObj = main::getModule('HTTPD')
                if ($console->{TYP} eq 'HTML') ;
        $loginObj = main::getModule('WAPD')
                if ($console->{TYP} eq 'WML') ;
        $user = $loginObj->{USER};
    }

    my $ret;
    if($console->typ ne 'AJAX') {
      push(@$ret, sprintf(gettext("%sThis is the xxv %s server.\nPlease use the following commands:\n"),
          ($hint ? "$hint\n\n" : ''), $console->typ));
    }
    $console->setCall('help');
    my $mods = main::getModules();
    my @realModName;

    # Search for command and display the Description
    foreach my $modName (sort keys %{$mods}) {
        my $modCfg = $mods->{$modName}->{MOD};

        my $name = $modCfg->{Name};
        error(sprintf("Missing real modul name %s",$modName)) unless($name);
        push(@realModName, $name) if($name);

        next if($modulename and uc($modulename) ne $name);
        foreach my $cmdName (sort keys %{$modCfg->{Commands}}) {
            push(@$ret,
                [
                    $modCfg->{Commands}->{$cmdName}->{short},
                    $cmdName,
                    (split('::', $modName))[-1],
                    $modCfg->{Commands}->{$cmdName}->{description},
                ]
            ) if(! $modCfg->{Commands}->{$cmdName}->{hidden} and ($u->{active} ne 'y') || $u->allowCommand($modCfg, $cmdName, $user, "1"));
        }
    }
    my $info = {
      rows => scalar @$ret
    };
    if($console->typ eq 'HTML') {
      $info->{periods} = $mods->{'XXV::MODULES::EPG'}->{periods};
      $info->{CHANNELS} =  $mods->{'XXV::MODULES::CHANNELS'}->ChannelWithGroup('c.name,c.hash');
      $info->{CONFIGS} = [ sort @realModName ];
    }
    $console->table( $ret, $info );
}

1;
