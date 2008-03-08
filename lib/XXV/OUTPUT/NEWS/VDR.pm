package XXV::OUTPUT::NEWS::VDR;
use strict;

use Tools;
use POSIX qw(locale_h);

# News Modules have only three methods
# init - for intervall or others
# send - send the informations
# read - read the news and parse it

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'NEWS::VDR',
        Description => gettext('This NEWS module generates messages for the VDR interface.'),
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
                    my $erg = $obj->init
                        or return undef, gettext("Can't initialize news module!")
                            if($value eq 'y' and not exists $obj->{INITE});
                    if($value eq 'y') {
                      my $emodule = main::getModule('EVENTS');
                      if(!$emodule or $emodule->{active} ne 'y') {
                        return undef, sprintf(gettext("Module can't activated! This module depends module %s."),'EVENTS');
                      }
                      my $rmodule = main::getModule('REPORT');
                      if(!$rmodule or $rmodule->{active} ne 'y') {
                        return undef, sprintf(gettext("Module can't activated! This module depends module %s."),'REPORT');
                      }
                    }
                    return $value;
                },
            },
            level => {
                description => gettext('Category of messages that should displayed'),
                default     => 1,
                type        => 'list',
                choices     => sub {
                                    my $rmodule = main::getModule('REPORT');
                                    return undef unless($rmodule);
                                    my $erg = $rmodule->get_level_as_array();
                                    map { my $x = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $x; } @$erg;
                                    return @$erg;
                                 },
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    my $rmodule = main::getModule('REPORT');
                    return undef unless($rmodule);
                    my $erg = $rmodule->get_level_as_array();
                    unless($value >= $erg->[0]->[0] and $value <= $erg->[-1]->[0]) {
                        return undef, 
                               sprintf(gettext('Sorry, but value must be between %d and %d'),
                                  $erg->[0]->[0],$erg->[-1]->[0]);
                    }
                    return $value;
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

    # host
    $self->{host} = delete $attr{'-host'};

	# who am I
    $self->{MOD} = $self->module;

    # all configvalues to $self without parents (important for ConfigModule)
    map {
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_} || $self->{MOD}->{Preferences}->{$_}->{default}
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{TYP} = 'text/plain';

    # Initiat after load modules ...
    main::after(sub{
        # The Initprocess
        my $erg = $self->init
            or return error("Can't initialize news module!");
    }, "NEWS::VDR: Start initiate news module ...")
        if($self->{active} eq 'y');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error('No object defined!');

    $obj->{INITE} = 1;
    $obj->{SVDRP} = main::getModule('SVDRP');

    1;
}

# ------------------
sub send {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error('No data defined!');

    return lg('This function is deactivated!')
        if($obj->{active} ne 'y');

    return lg('Title is not set!')
        unless($vars->{Title});


    my $cmd = sprintf('MESG %s', $vars->{Title});

    my $svdrp = $obj->{SVDRP} || return error ('No SVDRP!' );
    return $svdrp->command($cmd);
}

# ------------------
sub read {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error('No data defined!');

    return $obj->send($vars);
}

# ------------------
sub req {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $test = shift  || 0;

    return gettext('The module NEWS::VDR is not active!')
        if($obj->{active} ne 'y');

    my $vars = {
        AddDate => time,
        Title   => 'This is only a test from xxv news vdr modul!',
        Text    => 'This is only a test from xxv news vdr modul!',
        Cmd     => 'request',
        Id      => 'vdr',
        Level   => 'harmless',
    };

    if( $obj->read($vars) ) {
      return gettext("Message was been sent to your VDR!");
    } else {
      return gettext("Message chould'nt been sent to your VDR!");
    }
}


1;
