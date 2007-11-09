package XXV::MODULES::USER;

use strict;

use Tools;
use Locale::gettext;
use File::Path;


# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'USER',
        Prereq => {
            'Net::IP::Match::Regexp qw( create_iprange_regexp match_ip )'
                => 'Efficiently match IPv4 addresses against IPv4 ranges via regexp ',
        },
        Description =>
gettext("This module manages the User administration.
You may set a level for the whole module with 
the 'Level' parameter in the main module
or the same parameter is set for each function."),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Enable user authentication'),
                default     => 'y',
                type        => 'confirm',
            },
            withAuth => {
                description => gettext('IP addresses with user authentification'),
                default     => '',
                type        => 'string',
                check       => sub{
                    my $value = shift || return;
                    my @ips = split(/\s*,\s*/, $value);
                    for (@ips) {
                        return undef, sprintf(gettext('Your IP number (%s) is wrong! You need an IP in range (xxx.xxx.xxx.xxx/xx)'), $_)
                            unless ($_ =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d+/);
                    }
                    return $value;
                },
            },
            noAuth => {
                description => gettext('IP addresses without user authentification'),
                default     => '',
                type        => 'string',
                check       => sub{
                    my $value = shift || return;
                    my @ips = split(/\s*,\s*/, $value);
                    for (@ips) {
                        return undef, sprintf(gettext('Your IP number (%s) is wrong! You need an IP in range (xxx.xxx.xxx.xxx/xx)'), $_)
                            unless ($_ =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d+/);
                    }
                    return $value;
                },
            },
            tempimages => {
                description => gettext('common directory for temporary images'),
                default     => '/var/cache/xxv/temp',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            unew => {
                description => gettext('Create new user account'),
                short       => 'un',
                callback    => sub{ $obj->create(@_) },
                Level       => 'admin',
            },
            udelete => {
                description => gettext("Delete user account 'uid'"),
                short       => 'ud',
                callback    => sub{ $obj->delete(@_) },
                Level       => 'admin',
            },
            uedit => {
                description => gettext("Edit user account 'uid'"),
                short       => 'ue',
                callback    => sub{ $obj->edit(@_) },
                Level       => 'admin',
            },
            uprefs => {
                description => gettext("Change preferences"),
                short       => 'up',
                callback    => sub{ $obj->userprefs(@_) },
                Level       => 'user',
            },
            ulist => {
                description => gettext("List the accounts of users"),
                short       => 'ul',
                callback    => sub{ $obj->list(@_) },
                Level       => 'admin',
            },
            logout => {
                description => gettext("Log out from current session."),
                short       => 'exit',
                callback    => sub{
                    my $watcher = shift || return error('No watcher defined!');
                    my $console = shift || return error('No console defined!');

                    if($obj->{active} eq 'y') {
                        $console->message(gettext("Session closed."));
                        $console->redirect({url => '?', parent => 'top', wait => 2})
                            if($console->typ eq 'HTML');

                        my $ConsoleMod;
                        my $delayed = 0;
                        if($console->typ eq 'HTML' || $console->typ eq 'AJAX') {
                          $ConsoleMod = main::getModule('HTTPD');
                          $delayed = 1;
                        } elsif ($console->typ eq 'WML') {
                          $ConsoleMod = main::getModule('WAPD');
                          $delayed = 1;
                        } elsif ($console->typ eq 'CONSOLE') {
                          $ConsoleMod = main::getModule('TELNET');
                        };
  
                        if($delayed) {
                          # Close session delayed, give browser my time load depends files like style.css
                          Event->timer(
                              after => 1,
                              prio => 6,  # -1 very hard ... 6 very low
                              cb => sub{
                                  $obj->logout;
                                  delete $console->{USER} if($console->{USER});
                                  $ConsoleMod->{LOGOUT} = 1 if($ConsoleMod);
                              },
                          );
                        } else  {
                          $obj->logout;
                          delete $console->{USER} if($console->{USER});
                          $ConsoleMod->{LOGOUT} = 1 if($ConsoleMod);
                        }
                    }
                },
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
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
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

    return 0, panic("Session to database is'nt connected")
      unless($obj->{dbh});

    # don't remove old table, if updated rows => warn only
    tableUpdated($obj->{dbh},'USER',9,0);

    # Look for table or create this table
    my $version = main::getVersion;
    my $erg = $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS USER (
          Id int(11) unsigned auto_increment NOT NULL,
          Name varchar(100) NOT NULL default '',
          Password varchar(100) NOT NULL,
          Level set('admin', 'user', 'guest' ) NOT NULL,
          Prefs varchar(100) default '',
          UserPrefs varchar(100) default '',
          Deny set('tlist', 'alist', 'rlist', 'mlist', 'tedit', 'aedit', 'redit', 'remote', 'stream', 'cedit', 'media'),
          MaxLifeTime tinyint(2) default '0',
          MaxPriority tinyint(2) default '0',
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    # The Table is empty? Make a default User ...
    unless($obj->{dbh}->selectrow_arrayref('SELECT SQL_CACHE  count(*) from USER')->[0]) {
        $obj->_insert({
            Name => 'xxv',
            Password => 'xxv',
            Level => 'admin',
        });
    }
}


# ------------------
# Name:  create
# Descr: Save a new User in the Usertable.
# Usage: my $ok = $obj->create($watcher, $console, 0, {name => 'user', ...});
# ------------------
sub create {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || 0;
    my $data    = shift || 0;

    $obj->edit($watcher, $console, $id, $data);

}

# ------------------
sub userprefs {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || $obj->{USER}->{Id};
    my $data    = shift || 0;

    my $user;
    if($id and not ref $data) {
        my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  * from USER where Id = ?');
        $sth->execute($id)
            or return $console->err(sprintf(gettext("User account '%s' does not exist in the database!"),$id));
        $user = $sth->fetchrow_hashref();
    }

    my $questions = [
        'Id' => {
            typ     => 'hidden',
            def     => $user->{Id} || 0,
        },
        'Password' => {
            typ   => 'password',
            msg   => gettext("Password for this account"),
            req   => gettext('This is required!'),
            def   => '',
            check   => sub{
                my $value = shift || return;
                # If no password given the
                # take the old password as default
                if($console->typ eq 'HTML') {
                    if($value->[0] and $value->[0] ne $value->[1]) {
                        return undef, gettext("The fields with the 1st and the 2nd password must match!");
                    } else {
                        return $value->[0];
                    }
                }
                else {
                    return $value;
                }
            },
        },
        'UserPrefs' => {
            def     => $user->{UserPrefs} || '',
            msg     => gettext("Personal preferences for this user: ModName::Param=value, "),
            typ     => 'string',
            check   => sub{
                my $value = shift || return;
                foreach my $pref (split(',', $value)) {
                    my ($modname, $parameter, $value) = $pref =~ /(\S+)::(\S+)\=(.+)/sg;
                    if(my $mod = main::getModule($modname)) {
                        unless(exists $mod->{$parameter}) {
                            return undef, sprintf(gettext("The parameter '%s' in module '%s' does not exist!"),$parameter, $mod);
                        }
                    }
                }
                return $value;
            },
        },
    ];

    # Ask Questions
    $data = $console->question(sprintf(gettext('Edit preferences: %s'), $obj->{USER}->{Name}), $questions, $data);

    if(ref $data eq 'HASH') {
        $obj->_insert($data);

        $obj->refreshUserSettings($data->{UserPrefs}, $user->{UserPrefs});

        $console->message(gettext('User account saved!'));
        if($console->typ eq 'HTML') {
            $console->redirect({url => '?', parent => 'top', wait => 2});
            $console->message(gettext('Please wait ... refreshing interface!'));
        }
    }
    return 1;
}


# ------------------
# Name:  edit
# Descr: Edit an existing User in the Usertable.
# Usage: my $ok = $obj->edit($watcher, $console, $id, [$data]);
# ------------------
sub edit {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || 0;
    my $data    = shift || 0;

    my $user;
    if($id and not ref $data) {
        my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  * from USER where Id = ?');
        $sth->execute($id)
            or return $console->err(sprintf(gettext("User account '%s' does not exist in the database!"),$id));
        $user = $sth->fetchrow_hashref();

        # question erwartet ein Array
        my @deny = split(/\s*,\s*/, $user->{Deny});
        $user->{Deny} = \@deny;
    }

    my %l = (
        'admin' => gettext('Administrator'),
        'user' => gettext('User'),
        'guest' => gettext('Guest')
    );

    my $questions = [
        'Id' => {
            typ     => 'hidden',
            def     => $user->{Id} || 0,
        },
        'Name' => {
            msg   => gettext("Name of user account"),
            req   => gettext('This is required!'),
            def   => $user->{Name} || '',
        },
        'Password' => {
            typ   => 'password',
            msg   => gettext("Password for this account"),
            req   => gettext('This is required!'),
            def   => '',
            check   => sub{
                my $value = shift || return;
                # If no password given the
                # take the old password as default
                if($console->typ eq 'HTML') {
                    if($value->[0] and $value->[0] ne $value->[1]) {
                        return undef, gettext("The fields with the 1st and the 2nd password must match!");
                    } else {
                        return $value->[0];
                    }
                }
                else {
                    return $value;
                }
            },
        },
        'Level' => {
            def     => sub {
                            my $value = $user->{Level} || 'guest';
                            return $l{$value};
                          },
            msg     => gettext("Level for this account"),
            typ     => 'radio',
            req     => gettext('This is required!'),
            choices => [$l{'admin'},$l{'user'},$l{'guest'}],
            check   => sub{
                my $value = shift || return;
                my $data = shift || return error('No Data in CB');
                unless(grep($_ eq $value, @{$data->{choices}})) {
                     my $ch = join(' ', @{$data->{choices}});
                     return undef, sprintf(gettext("You can choose: %s!"),$ch);
                }
                foreach my $k (keys %l) {
                    return $k
                        if($value eq $l{$k});
                }
                my $ch = join(' ', @{$data->{choices}});
                return undef, sprintf(gettext("You can choose: %s!"),$ch);
            },
        },
        'Deny' => {
            msg   => gettext('Deny class of commands'),
            typ   => 'checkbox',
            choices   => ['tlist', 'alist', 'rlist', 'mlist', 'tedit', 'aedit', 'redit', 'remote', 'stream', 'cedit', 'media'],
            def   => $user->{Deny} || '',
            check   => sub{
                my $value = shift || '';
                my $data = shift || return error('No Data in CB');
                my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);

                foreach my $v (@vals) {
                    unless(grep($_ eq $v, @{$data->{choices}})) {
                        my $ch = join(' ', @{$data->{choices}});
                        return undef, sprintf(gettext("You can choose: %s!"),$ch);
                    }
                }
                return join(',', @vals);
            },
        },
        'Prefs' => {
            def     => $user->{Prefs} || '',
            msg     => gettext("Preferences for this User: ModName::Param=value, "),
            typ     => 'string',
            check   => sub{
                my $value = shift || return;
                foreach my $pref (split(',', $value)) {
                    my ($modname, $parameter, $value) = $pref =~ /(\S+)::(\S+)\=(.+)/sg;
                    if(my $mod = main::getModule($modname)) {
                        unless(exists $mod->{$parameter}) {
                            return undef, sprintf(gettext("The parameter '%s' in module '%s' does not exist!"),$parameter, $mod);
                        }
                    }
                }
                return $value;
            },
        },
        'MaxLifeTime' => {
            msg   => gettext("Maximum permitted value for lifetime with timers"),
            def   => $user->{MaxLifeTime} || '0',
            type  => 'integer',
            check   => sub{
                my $value = shift || return 0;
                unless(int($value) and int($value) > 0 and int($value) < 100) {
                    return undef, gettext("This value is not an integer or not between 0 and 100");
                }
                return $value;
            },
        },
        'MaxPriority' => {
            msg   => gettext("Maximum permitted value for priority with timers"),
            def   => $user->{MaxPriority} || '0',
            type  => 'integer',
            check   => sub{
                my $value = shift || return 0;
                unless(int($value) and int($value) > 0 and int($value) < 100) {
                    return undef, gettext("This value is not an integer or not between 0 and 100");
                }
                return $value;
            },
        },
    ];

    # Ask Questions
    $data = $console->question(($id ? gettext('Edit user account')
				    : gettext('Create new user account')), $questions, $data);

    if(ref $data eq 'HASH') {
        $obj->_insert($data);

        debug sprintf('%s account with name "%s" is saved%s',
            ($id ? 'New' : 'Changed'),
            $data->{Name},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $console->message(gettext('User account saved!'));
        $console->redirect({url => $console->{browser}->{Referer}, wait => 2})
            if($console->typ eq 'HTML');
    }
    return 1;
}

# ------------------
# Name:  delete
# Descr: Delete an existing User in the Usertable with Id.
# Usage: my $ok = $obj->delete($watcher, $console, $id);
# ------------------
sub delete {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id = shift || return $console->err(gettext("No user account defined for deletion! Please use udelete 'uid'."));

    my $sth = $obj->{dbh}->prepare('delete from USER where Id = ?');
    $sth->execute($id)
        or return $console->err(sprintf(gettext("User account '%s' does not exist in the database!"),$id));
    $console->message(sprintf gettext("User account %s deleted."), $id);

    debug sprintf('Delete user account "%s"%s',
        $id,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    $console->redirect({url => $console->{browser}->{Referer}, wait => 2})
        if($console->typ eq 'HTML');

}


# ------------------
sub list {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');

    my %f = (
        'Id' => umlaute(gettext('Service')),
        'Name' => umlaute(gettext('Name')),
        'Level' => umlaute(gettext('Level')),
        'Prefs' => umlaute(gettext('Preferences')),
        'UserPrefs' => umlaute(gettext('UserPreferences')),
    );

    my $sql = qq|
SELECT SQL_CACHE  
  Id as $f{Id}, 
  Name as $f{Name}, 
  Level as $f{Level}, 
  Prefs as $f{Prefs}, 
  UserPrefs as $f{UserPrefs} 
from 
  USER
    |;
    my $fields = fields($obj->{dbh}, $sql);

    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    unshift(@$erg, $fields);

    $console->table($erg);
}

# ------------------
# Name:  logout
# Descr: The routine for logout the user, this will clean the user temp files
#        and make a rollback to the standard user settings.
# Usage: my $ok = $obj->logout();
# ------------------
sub logout {
    my $obj = shift || return error('No object defined!');

    lg sprintf('Logout called%s',
        $obj->{USER}->{Name} ? sprintf(" by user %s", $obj->{USER}->{Name}) : "" 
        );

    # get the default user settings
    $obj->setUserSettings($obj->{USER}->{UserPrefs}, 'rollback')
        if($obj->{USER}->{UserPrefs});

    # get the default settings
    $obj->setUserSettings($obj->{USER}->{Prefs}, 'rollback')
        if($obj->{USER}->{Prefs});

    main::toCleanUp($obj->{USER}->{Name});
    delete $obj->{USER};
    return 1;
}

# ------------------
sub _checkIp {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $handle = shift || return;

    my $ip = getip($handle);

    if($obj->{withAuth}) {
        my $regexp = create_iprange_regexp(split(/\s*,\s*/, $obj->{withAuth}));
        if (match_ip($ip, $regexp)) {
           return 0;
        }
    }

    if($obj->{noAuth}) {
        my $regexp = create_iprange_regexp(split(/\s*,\s*/, $obj->{noAuth}));
        if (match_ip($ip, $regexp)) {
           return 1;
        }
    }
    return 0;
}

# ------------------
# Name:  check
# Descr: The loginroutine to check the User Name, Password
#        or the ClientIPAdress.
#        This will return a Userhash with the DB-Entrys.
# Usage: my $userHash = $obj->check($handle);
# ------------------
sub check {
    my $obj = shift || return error('No object defined!');
    my $handle = shift || return;

    if($obj->_checkIp($handle)) {
        $obj->{USER}->{Name} = undef;
        $obj->{USER}->{Level} = 'admin';
    } else {
        my $name = shift || return;
        my $password = shift || return;


        my $oldprefs = $obj->{USER}->{UserPrefs};

        my $newUser = 0;
        if((!$obj->{USER}) or (!scalar keys %{$obj->{USER}}) or $name ne $obj->{USER}->{Name}) {
            lg sprintf('User %s try to login!', $name );
            $newUser = $name;
            $obj->logout()
                if($obj->{USER} and (scalar keys %{$obj->{USER}}));
        }

        # check User
        my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  * from USER where Name = ? and Password = md5( ? )');
        $sth->execute($name, $password)
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $obj->{USER} = $sth->fetchrow_hashref();

        # Set the user settings from user
        $obj->refreshUserSettings($obj->{USER}->{UserPrefs}, $oldprefs);

        # Set the user settings from admin
        $obj->setUserSettings($obj->{USER}->{Prefs}, 'set')
            if($obj->{USER}->{Prefs} and $newUser);
    }

    if(my $level = $obj->getLevel($obj->{USER}->{Level})) {
        $obj->{USER}->{value} = $level if($level);
    }

    return $obj->{USER};
}

# ------------------
sub refreshUserSettings {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $newprefs = shift || '';
    my $oldprefs = shift || '';

    return 1 if($newprefs eq $oldprefs);

    $obj->setUserSettings($oldprefs, 'rollback')
        if($oldprefs);

    $obj->setUserSettings($newprefs, 'set')
        if($newprefs);

    my $mod = main::getModule('CONFIG');
    $mod->reconfigure();

}


# ------------------
sub setUserSettings {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $prefs = shift || return error ('No Settings??');
    my $mode = shift || 'set';

    foreach my $pref (split(',', $prefs)) {
        my ($modname, $parameter, $value) = $pref =~ /(\S+)::(\S+)\=(.*)/sg;
        if($modname and my $mod = main::getModule($modname) and my $cfg = main::getModule('CONFIG')->{config}) {
            if(exists $mod->{$parameter}) {
                if($mode eq 'set') {
                    $cfg->{$modname}->{$parameter} = $value;
                } else {
                    $cfg->{$modname}->{$parameter} = $mod->{$parameter};
                }
            } else {
                error("The Parameter '$parameter' in Module '$mod' is doesn't exist!");
            }
        }
    }
}

# ------------------
sub allowCommand {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $modCfg = shift || return error('No modul defined!');
    my $cmdName = shift || return error('No command name defined!');
    my $user = shift || return error('No user defined!');
    my $DontdumpViolation = shift || '';

    if(
        (exists $modCfg->{Level} and $user->{value} < $obj->getLevel($modCfg->{Level}))
        or
        (exists $modCfg->{Commands}->{$cmdName}->{Level} and $user->{value} < $obj->getLevel($modCfg->{Commands}->{$cmdName}->{Level}))
        or
        ($user->{Deny} and exists $modCfg->{Commands}->{$cmdName}->{DenyClass} and $user->{Deny} =~ /$modCfg->{Commands}->{$cmdName}->{DenyClass}/)
    ) {
        error(sprintf('User %s with Level %s has try to call command %s without permissions!',
            $user->{Name}, $user->{Level}, $cmdName))
		if($DontdumpViolation eq '');
        return 0;
    }
    return 1;
}

# ------------------
# Name:  checkCommand
# Descr: A routine to check the commands, translate the shortcuts.
#        This will return the cmdobj and cmdname if this command ok.
#        $shorterr is set in following Errorcases:
#           'noactive'  = Plugin is not set active
#           'noperm'    = Permission denied for the called User
#           'noexists'  = Command does not exist!
#        $error is the full Errortext to diaply im Userinterface.
# Usage: my ($cmdobj, $cmdname, $shorterr, $error) = $obj->checkCommand($console, $command);
# Test:
sub t_checkCommand {
    my ($cmdobj, $cmdname, $shorterr, $error, $t)
        = $_[0]->checkCommand($_[1], 'tl');
    $t = 1 if(ref $cmdobj and $cmdname eq 'tlist');
    ($cmdobj, $cmdname, $shorterr, $error)
        = $_[0]->checkCommand($_[1], 'lalalalal');
    $t = 1 if(not ref $cmdobj and not $cmdname and $shorterr and $error);
    return $t;
}
# ------------------
sub checkCommand {
    my $obj = shift  || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $ucmd = shift || return error('No command defined!');
    my $DontdumpViolation = shift || '';

    my $mods = main::getModules();
    my $err = 0;
    my $shorterr = 0;
    my $cmdobj = 0;
    my $cmdname = 0;
    my $cfg = main::getModule('CONFIG')->{config};
    my $ok = 0;

    # Checks the Commands Syntax (double shortcmds?)
    $obj->checkCmdSyntax()
        unless(defined $obj->{Check});

    foreach my $modName (keys %{$mods}) {
        my $modCfg = $mods->{$modName}->{MOD};
        foreach my $cmdName (sort keys %{$modCfg->{Commands}}) {
            if(lc($ucmd) eq $cmdName or (exists $modCfg->{Commands}->{$cmdName}->{short} and lc($ucmd) eq $modCfg->{Commands}->{$cmdName}->{short})) {
                $ok++;
                $cmdobj = $modCfg->{Commands}->{$cmdName};
                $cmdname = $cmdName;
                # Check on active Modul
                if(exists $mods->{$modName}->{active} and $cfg->{$modCfg->{Name}}->{active} eq 'n') {
                    $err = sprintf(gettext("Sorry, but the module %s is inactive! Enable it with %s:Preferences:active = y"),
                        $modCfg->{Name}, $modCfg->{Name});
                    $shorterr = 'noactive';
                }

                if($obj->{active} eq 'y') {
                    # Check Userlevel and Permissions
                    unless($obj->allowCommand($modCfg, $cmdName, $console->{USER},$DontdumpViolation)) {
                        $err = gettext('You are not authorized for this function!');
                        $shorterr = 'noperm';
                    }
                }
            }
        }
    }
    unless($ok) {
        $err = sprintf(gettext("Sorry, couldn't understand command '%s'!\n"), $ucmd);
        $shorterr = 'noexists';
    }

    if($shorterr) {
        return (undef, 'nothing', $shorterr, $err)
    } else {
        return ($cmdobj, $cmdname, undef, undef)
    }
}

# ------------------
# Name:  checkCmdSyntax
# Descr: Check the Syntax of Commands and for double Names in different Modules
# Usage: my $ok = $obj->checkCmdSyntax(tlist);
# Test:
sub t_checkCmdSyntax {
    return $_[0]->checkCmdSyntax('tlist');
}
# ------------------
sub checkCmdSyntax {
    my $obj     = shift || return error('No object defined!');
    my $mods    = main::getModules();

    my $shorts = {};
    foreach my $modName (keys %{$mods}) {
        my $modCfg = $mods->{$modName}->{MOD};
        foreach my $cmdName (sort keys %{$modCfg->{Commands}}) {
            my $short = $modCfg->{Commands}->{$cmdName}->{short} || $cmdName;
            if(exists $shorts->{$short} ) {
                return error sprintf("[ERROR] In %s::%s double short name %s, also in %s!",
                    $modName, $cmdName, $short, $shorts->{$short});
            } else {
                $shorts->{$short} = $modName.'::'.$cmdName;
            }
        }
    }
    $obj->{Check} = 1;
    1;
}

# ------------------
# Name:  getLevel
# Descr: Translate the Levelname to an numeric level
# Usage: my $score = $obj->getLevel(levelname);
# Test:
sub t_getLevel {
    return $_[0]->getLevel('user') == 5;
}
# ------------------
sub getLevel {
    my $obj = shift || return error('No object defined!');
    my $name = shift || return;

    # Level Table
    $obj->{LEV} = {
        admin   => 10,
        user    => 5,
        guest   => 1,
    } unless(exists $obj->{LEV});

    if($obj->{LEV}->{$name}) {
        return $obj->{LEV}->{$name};
    } else {
        return error("This Levelname '$name' does not exist");
    }

}

# ------------------
sub _insert {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $data = shift || return;

    if(ref $data eq 'HASH') {
        my ($names, $vals, $kenn);
        map {

            if($_ eq 'Password') {
                if($data->{Password}) {
                    push(@$names, $_);
                    push(@$vals, $data->{$_});
                    push(@$kenn, 'MD5(?)');
                }
            } else {
                push(@$names, $_);
                push(@$vals, $data->{$_});
                push(@$kenn, '?');
            }

        } sort keys %$data;

        my $sql;
        if($data->{Id}) {
            my $temp = [];
            my $c = 0;
            foreach (@$names) {
                push(@$temp, sprintf("%s=%s", $names->[$c], $kenn->[$c]));
                $c++;
            }
            $sql = sprintf("UPDATE USER SET %s WHERE Id = %lu",
                    join(', ', @$temp),
                    $data->{Id},
            );
        } else {
            $sql = sprintf("REPLACE INTO USER (%s) VALUES (%s)",
                    join(', ', @$names),
                    join(', ', @$kenn),
            );
        }
        my $sth = $obj->{dbh}->prepare( $sql );
        $sth->execute( @$vals );
    } else {
        my $sth = $obj->{dbh}->prepare('REPLACE INTO USER VALUES (?,?,?,?)');
        $sth->execute( @$data );
    }
}

# ------------------
# Name:  userTmp
# Descr: Return a temp directory only for logged user and delete this by exit xxv.
# Usage: my $tmpdir = $obj->userTmp([username]);
# ------------------
sub userTmp {
    my $obj = shift  || return error('No object defined!');
    my $user = ($obj->{active} eq 'y' ?  ( shift  || ($obj->{USER}->{Name}?$obj->{USER}->{Name}:"nobody") ) : "nobody" );

    # /var/cache/xxv/temp/xpix/$PID
    my $dir = sprintf('%s/%s/%d', $obj->{tempimages} , $user, $$);

    unless(-d $dir) {
        mkpath($dir) or error "Couldn't mkpath $dir : $!";
    }

    # Nach Logout oder beenden von xxv das temp löschen
    main::toCleanUp($user, sub{ deleteDir($dir) }, 'logout')
        unless(main::toCleanUp($user, undef, 'exists')); # ein CB registrieren

    return $dir;
}

1;
