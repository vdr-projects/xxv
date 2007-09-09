package XXV::MODULES::REMOTE;

use strict;

use Tools;
use Locale::gettext;
# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'REMOTE',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module emulate a remote control.'),
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
            },
            monitor => {
                description => gettext('Grab video framebuffer, as preview on remotecontrol.'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            commands => {
                description => sprintf(gettext("Path of file '%s'"),'commands.conf'),
                default     => '/var/lib/vdr/commands.conf',
                type        => 'file',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            remote => {
                description => gettext("Display ir remote 'cmd'"),
                short       => 'r',
                callback    => sub{ $obj->remote(@_) },
                DenyClass   => 'remote',
            },
            switch => {
                description => gettext("Switch to channel 'cid'"),
                short       => 'sw',
                callback    => sub{ $obj->switch(@_) },
                DenyClass   => 'remote',
            },
            command => {
                description => gettext("Call the command 'cid'"),
                short       => 'cmd',
                callback    => sub{ $obj->command(@_) },
                DenyClass   => 'remote',
            },
            cmdlist => {
                description => gettext("List the commands"),
                short       => 'cmdl',
                callback    => sub{ $obj->list(@_) },
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

    $self->init or return error('Problem to initialize module');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift  || return error('No object defined!');

    main::after(sub{
          $obj->{svdrp} = main::getModule('SVDRP');
          unless($obj->{svdrp}) {
            panic ("Can't get modul SVDRP");
            return 0;
          }

          $obj->{CMDS} = $obj->parse();
          return 1;
        }, "REMOTE: Parse Commandfile ...");

    return 1;
}

# ------------------
sub parse {
# ------------------
    my $obj = shift  || return error('No object defined!');

    return 0
        unless (exists $obj->{commands});

    if(! -r $obj->{commands}) {
        error (sprintf("Could not open file '%s'! : %s",$obj->{commands},$!));
        return 0;
    }

    my $cmds = load_file($obj->{commands});

    my $c = 0;
    my $ret = {};
    foreach my $zeile (split("\n", $cmds)) {
        next if($zeile =~ /^\#/);
        my ($cmd, $batch) = split('\s*\:\s*', $zeile);

        $ret->{$c++} = {
            cmd => $cmd,
            bat => $batch,
        } if($cmd and $batch);
    }
    return $ret;
}

# ------------------
sub list {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $cmds = $obj->parse();

    my @list = (['__Id', 'Name', 'Cmd']);
    foreach my $id (sort {$a <=> $b} keys %$cmds) {
        push(@list, [$id, $cmds->{$id}->{cmd}, $cmds->{$id}->{bat}]);
    }

    return $console->table(\@list);
}

# ------------------
sub command {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $command = shift || return error ('No Command!');
    my $cmds = $obj->parse();

    return $console->err(gettext('This cmd id does not exist!'))
        unless(exists $cmds->{$command});

    $console->message(my $msg = sprintf(gettext('Try to start command: %s with cmd: %s'),
        $cmds->{$command}->{cmd}, $cmds->{$command}->{bat}));

    lg $msg;

    my $out;
    open(README, "$cmds->{$command}->{bat} 2>&1 |") or return error("Can't run program: $!");
    while(<README>) {
        $out .= $_;
    }
    close(README);
    return $console->message($out,  {
                                        tags => {
                                           first => "<pre>", 
                                           last => "</pre>"
                                        }
                                    } );
}


# ------------------
sub remote {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $command = shift;

    debug sprintf('Call remote with command "%s"%s',
        $command,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    unless($command) {
        my $mod = main::getModule('GRAB');
        my $params = {
            width => $mod->{xsize},
            height => $mod->{ysize},
            monitor => $obj->{monitor} eq "y" ? 1 : 0
        };
        return $console->remote(undef, $params);
    } else {
        # the svdrp module
        my $svdrp = $obj->{svdrp};

        my $translate = {
            '<' => 'Channel-',
            '>' => 'Channel+',
            '+' => 'Volume+',
            '-' => 'Volume-',
            '>>' => 'FastFwd',
            '<<' => 'FastRew',
            'VolumePlus' => 'Volume+',
            'VolumeMinus' => 'Volume-',
            'Null' => '0',
        };

        $command = $translate->{$command}
            if(exists $translate->{$command});

        # the command
        my $cmd = sprintf('hitk %s', $command);
        my $erg = $svdrp->command($cmd);

        $console->msg($erg, $svdrp->err)
            if(ref $console);
    }
    return 1;
}

# ------------------
sub switch {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $channel = shift || '';

    lg sprintf('Call switch with channel "%s"%s',
        $channel,
        ( ref $console && $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    # the svdrp module
    my $svdrp = $obj->{svdrp};

    # the command
    my $cmd = sprintf('chan %s', $channel);
    my $erg = $svdrp->command($cmd);

    my ($ret) = $erg->[1] =~ /^\d{3}\s*(.+)/s;

    $console->msg($erg, $svdrp->err)
        if(ref $console);
    $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
        if(ref $console and $console->typ eq 'HTML');


    return $ret;
}

1;
