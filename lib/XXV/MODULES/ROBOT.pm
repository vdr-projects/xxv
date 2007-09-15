package XXV::MODULES::ROBOT;
use strict;

use Tools;
use Locale::gettext;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'ROBOT',
        Prereq => {
#            'WWW::Mechanize' => 'Handy web browsing in a Perl object ',
        },
        Description => gettext('This module register and run robots to fetch data from internet.'),
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
            robot => {
                description => gettext("Start a robots 'rname'"),
                short       => 'ro',
                callback    => sub{ $obj->start(@_) },
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

	return $self;
}

# ------------------
sub saveRobot {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $rname = shift || return error('No robot name defined!');
    my $rsub = shift || return error('No robot subroutine defined!');

    return error("$rname is not a code reference!'")
        unless(ref $rsub eq 'CODE');

    $obj->clean( $rname );
    $obj->{robots}->{$rname} = $rsub;
    return $obj->{robots}->{$rname};
}

# ------------------
sub register {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $rname = shift || return error('No robot name defined!');
    my @args = @_;

    return error("$rname is not a Robot!'")
        unless(ref $obj->{robots}->{$rname} eq 'CODE');

    push(@{$obj->{jobs}->{$rname}}, [@args]);
}

# ------------------
sub start {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $rname = shift || return error('No robot name defined!');
    my $watcher = shift;
    my $console = shift;
    my $endcb   = shift;

    lg sprintf('Start Robots ....');

    unless(exists $obj->{jobs}->{$rname}) {
        return error("No Robot with name $rname is registered!");
    }

    # fork and forget
    defined(my $child = fork()) or die "Couldn't fork: $!";
    if($child == 0) {
        $obj->{dbh}->{InactiveDestroy} = 1;
        # create a new browser
        my $count = 0;
        foreach my $args (@{$obj->{jobs}->{$rname}}) {
            my ($result, $error);
            lg sprintf('robot callback %s started (%d)....', $rname, $count);
            eval {
                ($result, $error) = &{$obj->{robots}->{$rname}}(@$args);
            };
            $error = $@ if($@);
            if($result) {
                lg sprintf("robot callback %s successfully ended!", $rname);
            } else {
                error sprintf("robot callback %s failed! : %s ", $rname, $error);
            }
            $count++;
        }
        &$endcb()
            if(ref $endcb eq 'CODE');
        exit(0);
    }
}

# ------------------
sub clean {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $rname = shift || return error('No robot name defined!');
    delete $obj->{jobs}->{$rname};
}


# ------------------
sub result {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $rname = shift || return error('No robot name defined!');

    return $obj->{result}->{$rname};

}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $rname = shift;

    return 1 unless(ref $console);

    if($rname) {
        $console->table($obj->{result}->{$rname});
    } else {
        $console->table($obj->{result});
    }
}



1;
