package XXV::MODULES::WAPD;

use Locale::gettext;
use XXV::OUTPUT::Wml;
use File::Basename;
use File::Find;
use Tools;

use strict;

my $mime = {
    wml => "text/vnd.wap.wml",                 # WML-Dateien (WAP)
    wmlc => "application/vnd.wap.wmlc",        # WMLC-Dateien (WAP)
    wmls => "text/vnd.wap.wmlscript",          # WML-Scriptdateien (WAP)
    wmlsc => "application/vnd.wap.wmlscriptc", # WML-Script-C-dateien (WAP)
    wbm => "image/vnd.wap.wbmp",              # Bitmap-Dateien (WAP)
    wbmp  => "image/vnd.wap.wbmp"              # Bitmap-Dateien (WAP)
};

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'WAPD',
        Prereq => {
            'IO::Socket::INET'  => 'Object interface for AF_INET domain sockets ',
            'MIME::Base64'      => 'Encoding and decoding of base64 strings',
            'CGI qw/:push -nph -no_xhtml -compile/'
                                => 'Simple Common Gateway Interface Class',
        },
        Description => gettext('This module is a multisession WAPD server.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            Clients => {
                description => gettext('Maximum number from simultaneous connections to the same time'),
                default     => 5,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            Port => {
                description => gettext('Number of port to listen for wap clients'),
                default     => 8085,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            Interface => {
                description => gettext('Local interface to bind service'),
                default     => '0.0.0.0',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            WMLRoot => {
                description => gettext('Used Skin'),
                default     => 'wml',
                type        => 'list',
                required    => gettext('This is required!'),
                choices     => $obj->findskins,
            },
#            StartPage => {
#                description => gettext('First page, which is to be seen when logon'),
#                default     => 'now',
#                type        => 'list',
#                required    => gettext('This is required!'),
#                choices     => [
#                    [ gettext('Running now'),     'now'],
#                    [ gettext('Program guide'),   'program'],
#                    [ gettext('Autotimer'),       'alist'],
#                    [ gettext('Timers'),          'tlist'],
#                    [ gettext('Recordings'),      'rlist'],
#                    [ gettext('Music'),           'mlist'],
#                    [ gettext('Remote'),          'remote'],
#                    [ gettext('Teletext'),        'vtxpage'],
#                    [ gettext('Status'),          'sa'],
#                ],
#			},
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

    # globals
    my $channels;

    # make socket
	my $socket = IO::Socket::INET->new(
		Listen		=> $obj->{Clients},
		LocalPort	=> $obj->{Port},
    LocalAddr => $obj->{Interface},
		Reuse		=> 1
    ) or return error("Can't create Socket: $!");

    # install an initial watcher
    Event->io(
        fd => $socket,
        prio => -1,  # -1 very hard ... 6 very low
        cb => sub {
            # accept client
            my $client=$socket->accept;
            panic "Can't connect wapd to new client." and return unless $client;
            $client->autoflush;

            # make "channel" number
            my $channel=++$channels;

            # install a communicator
            Event->io(
                fd => $client,
                poll => 'r',
                prio => -1,  # -1 very hard ... 6 very low
                cb => sub {
                    my $watcher = shift;

                    # read new line and report it
                    my $handle=$watcher->w->fd;

                    my $data = $obj->parseRequest($handle,(defined $obj->{LOGOUT} && $obj->{LOGOUT} == 1 ));
                    unless($data) {
                        undef $obj->{LOGOUT};
                        $watcher->w->cancel;
                        $handle->close();
                        undef $watcher;
                        return 1;
                    }

                    undef $obj->{LOGOUT}
                        if(exists $obj->{LOGOUT});

                    my $WMLRootDir = sprintf('%s/%s', $obj->{paths}->{HTMLDIR}, $obj->{WMLRoot});
                    my $cgi = CGI->new( $data->{Query} );

                    my $console = XXV::OUTPUT::Wml->new(
                        -handle => $handle,
                        -dbh    => $obj->{dbh},
                        -wmldir => $WMLRootDir,
                        -cgi    => $cgi,
                        -mime   => $mime,
                        -browser=> $data,
                        -paths  => $obj->{paths},
#						-start  => $obj->{StartPage},
                    );

                    my $userMod = main::getModule('USER');
                    if(ref $userMod and $userMod->{active} eq 'y') {
                        $console->{USER} = $userMod->check($handle, $data->{username}, $data->{password});
                        $console->login(gettext('You have no permissions to this system!'))
                            unless(exists $console->{USER}->{Level});
                    }

                    if(ref $userMod and
                            ($userMod->{active} ne 'y'
                                or exists $console->{USER}->{Level})) {

                        $console->{call} = 'nothing';
                        if(($data->{Request} eq '/' or $data->{Request} =~ /\.WML$/) and not $data->{Query}) {
                            # Send the first page (wapd.tmpl)
                            my $page = $data->{Request};
                            if($page eq '/') {
                                if(-r sprintf('%s/wapd.tmpl', $WMLRootDir)) {
                                    $console->{call} = 'wapd';
                                    my $output = $console->parseTemplate('wapd','wapd');
                                    $console->out( $output );
                                } else {
                                    $console->datei(sprintf('%s/index.WML', $WMLRootDir));
                                }
                            } else {
                                $console->datei(sprintf('%s/%s', $WMLRootDir, $page));
                            }
                        } elsif(my $typ = $mime->{lc((split('\.', $data->{Request}))[-1])}) {
                            # Send multimedia files (this must registered in $mime!)
                            $console->image(sprintf('%s%s', $WMLRootDir, $data->{Request}), $typ);
                        } elsif( $cgi->param('binary') ) {
                            # Send multimedia files (if param binary)
                            $obj->handleInput($watcher, $console, $cgi);
                        } else {
                            $console->start();
                            $obj->handleInput($watcher, $console, $cgi);
                            $console->footer();
                        }
                    }
                    $watcher->w->cancel;
                    undef $watcher;
                    $handle->close();
                },
            );

        },
    ) if($obj->{active} eq 'y');

    return 1;

}

# ------------------
sub parseRequest {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $hdl = shift || return error ('No Handle!' );
    my $logout = shift || 0;

    my ($Req, $size) = getFromSocket($hdl);

       if($Req->[0] =~ /^GET (\/[\w\.\/-\:\%]*)([\?[\w=&\.\+\%-\:\!]*]*)[\#\d ]+HTTP\/1.\d$/) {
        my $data = {};
		($data->{Request}, $data->{Query}) = ($1, $2 ? substr($2, 1, length($2)) : undef);

    	# parse header
    	foreach my $line (@$Req) {
    		if($line =~ /Referer: (.*)/) {
    			$data->{Referer} = $1;
    		}
    		if($line =~ /Host: (.*)/) {
    			$data->{HOST} = $1;
    		}
    		if($line =~ /Authorization: basic (.*)/i and not $logout) {
    			($data->{username}, $data->{password}) = split(":", MIME::Base64::decode_base64($1), 2);
    		}
    		if($line =~ /User-Agent: (.*)/i) {
    			$data->{http_useragent} = $1;
    		}
    	}
        $data->{Request} =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

        return $data;
	} else {
           error sprintf("Unknown Request: <%s>\n", join("\n", @$Req));
	   return;
	}

}

# ------------------
sub handleInput {
# ------------------
    my $obj     = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $cgi     = shift || return error ('No CGI Object');

    my $ucmd    = $cgi->param('cmd')  || '<undef>';
    my $udata   = $cgi->param('data') || '';

    # Set the referer, if come a form with a error
    # then patch the referer
    $console->{browser}->{Referer} = $cgi->param('referer')
        if($cgi->param('referer'));

    # Test on result set (user has save) and
    # get the DataVars in a special Hash
    my $result;
    foreach my $name ($cgi->param) {
        if(my ($n) = $name =~ /^__(.+)/sig) {
            my @vals = $cgi->param($name);
            if(scalar @vals > 1) {
                @{$result->{$n}} = @vals;
            } else {
                $result->{$n} = shift @vals;
            }
        }
    }

    # Test the command on exists, permissions and so on
    my $u = main::getModule('USER');
    my ($cmdobj, $cmdname, $shorterr, $err) = $u->checkCommand($console, $ucmd);
    $console->{call} = $cmdname;
    if($cmdobj and not $shorterr) {
        $cmdobj->{callback}($watcher, $console, $udata, $result );
    } elsif($shorterr eq 'noperm' or $shorterr eq 'noactive') {
        return $console->status403($err);
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

# ------------------
sub findskins
# ------------------
{
    my $obj = shift || return error ('No Object!' );
    my $found;
    find({ wanted => sub{
                if(-d $File::Find::name and -e $File::Find::name.'/wapd.tmpl' ) {
                    my $l = basename($File::Find::name);
                    push(@{$found},[$l,$l]);
                }
           },
           follow => 1,
           follow_skip => 2,
        },
        $obj->{paths}->{HTMLDIR}
    );
    error "Can't find useful WML Skin at : $obj->{paths}->{HTMLDIR}"
        if(scalar $found == 0);
    return $found;
}

1;
