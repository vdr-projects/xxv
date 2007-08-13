package XXV::OUTPUT::NEWS::VDR;
use strict;

use Tools;
use POSIX qw(locale_h);
use Locale::gettext;

# News Modules have only three methods
# init - for intervall or others
# send - send the informations
# read - read the news and parse it

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'NEWS::VDR',
        Description => gettext('This NEWS module generate a messages for vdr interface.'),
        Version => '0.01',
        Date => '31.09.2005',
        Author => 'xpix',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'n',
                type        => 'confirm',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = shift;
                    my $erg = $obj->init
                        or return error('Problem to initialize news module')
                            if($value eq 'y' and not exists $obj->{INITE});
                    return $value;
                },
            },
            level => {
                description => gettext('Minimum level of the messages which can be displayed (1 ... 100)'),
                default     => 1,
                type        => 'integer',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    unless($value >= 1 and $value <= 100) {
                        return undef, 'Sorry, but the value must be between 1 and 100';
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
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{TYP} = 'text/plain';

    # Initiat after load modules ...
    main::after(sub{
        # The Initprocess
        my $erg = $self->init
            or return error('Problem to initialize news module');
    }, "NEWS::VDR: Start initiate the News vdr module ...")
        if($self->{active} eq 'y');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $url = sprintf("http://%s:%s/", $obj->{host}, main::getModule('HTTPD')->{Port});
    $obj->{INITE} = 1;

    $obj->{SVDRP} = main::getModule('SVDRP');

    1;
}

# ------------------
sub send {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $vars = shift || return error ('No Vars!' );

    return undef, lg('This function is deactivated!')
        if($obj->{active} ne 'y');

    return undef, lg('Title is not set!')
        unless($vars->{Title});


    my $cmd = sprintf('MESG %s', $vars->{Title});

    my $svdrp = $obj->{SVDRP} || return error ('No SVDRP!' );
    $svdrp->command($cmd);

    1;
}

# ------------------
sub read {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $vars = shift || return error ('No News!' );

    return $obj->send($vars);

    1;
}

# ------------------
sub req {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $test = shift  || 0;

    return gettext('The Module NEWS::VDR is not active!')
        if($obj->{active} ne 'y');

    my $vars = {
        AddDate => time,
        Title   => 'This is only a Test for the xxv news vdr module!',
        Text    => 'This is only a Test for the xxv news vdr module!',
        Cmd     => 'request',
        Id      => 'vdr',
        Url     => sprintf("http://%s:%s/", $obj->{host}, main::getModule('HTTPD')->{Port}),
        Level   => 'harmless',
    };
    $obj->read($vars);

    return gettext('A message is send to your SVDRPServer!');

}


1;
