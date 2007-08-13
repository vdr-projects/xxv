package XXV::MODULES::INTERFACE;

use Locale::gettext;
use XXV::OUTPUT::Dump;
use Tools;


use strict;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'INTERFACE',
        Prereq => {
            'IO::Socket::INET'           => 'Object interface for AF_INET domain sockets ',
            "SOAP::Lite"                 => 'Client and server side SOAP implementation',
            "SOAP::Transport::HTTP"      => 'Server/Client side HTTP support for SOAP::Lite',
            "SOAP::Transport::HTTP::Event" => 'Server/Client side HTTP support for SOAP::Lite',
        },
        Description => gettext('This module is a multichannel soap server for second party software.'),
        Version => '0.01',
        Date => '06.09.2004',
        Author => 'xpix',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            LocalPort => {
                description => gettext('Number of port to listen for soap clients'),
                default     => 8082,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            Interface => {
                description => gettext('Local interface to bind service'),
                default     => '0.0.0.0',
                type        => 'host',
                required    => gettext('This is required!'),
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
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_} || '';
        $self->{$_} = $self->{MOD}->{Preferences}->{$_}->{default} unless($self->{$_});
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # The Initprocess
    $self->init or return error('Problem to initialize module');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    if($obj->{active} eq 'y') {

        # Install the SOAP Server
        my $daemon = SOAP::Transport::HTTP::Event
            -> new (
                LocalAddr => $obj->{Interface},
                LocalPort => $obj->{LocalPort},
            )
            -> dispatch_to('SOAPService');

        debug("Install the SOAP server at %s", $daemon->url);
        my ($sock, $httpd) = $daemon->getDaemon();

        Event->io(
            fd => $sock,
            prio => -1,  # -1 very hard ... 6 very low
            cb => sub {
                $daemon->handle($sock, $httpd);
            }
        );
    }

    return 1;

}


1;

BEGIN {

    package SOAPService;

    use vars qw(@ISA);
#    @ISA = qw(Exporter SOAP::Server::Parameters);
    use SOAP::Lite;
    use Tools;

    # ------------------
    # Name:  getCommand
    # Descr: Call every commands.
    # Usage: my $data = $obj->getCommand($cmd, [$data, $params]);
    # ------------------
    sub getCommand {
        my $obj = shift || return error ('No Object!' );
        my $cmd = shift || return error ('No Command!' );
        my $data = shift;

        my $ret = $obj->handleInput($cmd, $data);
        return $ret;
    }

    # ------------------
    sub handleInput {
    # ------------------
        my $obj     = shift || return error ('No Object!' );
        my $ucmd    = shift || return error ('No Command');
        my $udata   = shift;

        my $watcher = $obj;

        my $console = XXV::OUTPUT::Dump->new();
        $console->{USER}->{Name} = undef;
        $console->{USER}->{Level} = 'admin';
        $console->{USER}->{value} = 10;

        # Test the command on exists, permissions and so on
        my $u = main::getModule('USER');
        my ($cmdobj, $cmdname, $shorterr, $err) = $u->checkCommand($console, $ucmd);
        $console->{call} = $cmdname;
        if($cmdobj and not $shorterr) {
            my @ret = $cmdobj->{callback}($watcher, $console, $udata);
            return \@ret;
        } elsif($shorterr eq 'noperm' or $shorterr eq 'noactive') {
            return $console->err($err);
        } else {
            return $obj->usage($watcher, $console, undef, $err);
        }
    }

    # ------------------
    sub usage {
    # ------------------
        my $obj = shift || return error ('No Object!' );
        return main::getModule('TELNET')->usage(@_);
    }

} # End BEGIN

1;
