package XXV::MODULES::WAPD;

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
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'WAPD',
        Prereq => {
            'IO::Socket::INET'  => 'Object interface for AF_INET domain sockets ',
            'MIME::Base64'      => 'Encoding and decoding of base64 strings',
            'CGI qw/:push -nph -no_xhtml -compile/'
                                => 'Simple Common Gateway Interface Class',
        },
        Description => gettext('This module is a multisession WAPD server.'),
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
            Clients => {
                description => gettext('Maximum number of simultaneous connections'),
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
                description => gettext('Skin used'),
                default     => 'wml',
                type        => 'list',
                required    => gettext('This is required!'),
                choices     => $self->findskins,
            },
#            StartPage => {
#                description => gettext('Startup screen'),
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

    $self->{charset} = delete $attr{'-charset'};
    if($self->{charset} eq 'UTF-8'){
      eval 'use utf8';
    }

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
        if($@) {
          my $m = (split(/ /, $_))[0];
          return panic("\nCouldn't load perl module: $m\nPlease install this module on your system:\nperl -MCPAN -e 'install $m'");
        }
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # The Initprocess
    $self->init or return error('Problem to initialize modul!');

	return $self;
}


# ------------------
sub init {
# ------------------
    my $self = shift || return error('No object defined!');

    # globals
    my $channels;

    # make socket
	my $socket = IO::Socket::INET->new(
		Listen		=> $self->{Clients},
		LocalPort	=> $self->{Port},
    LocalAddr => $self->{Interface},
		Reuse		=> 1
    ) or return error("Couldn't create socket: $!");

    # install an initial watcher
    Event->io(
        fd => $socket,
        prio => -1,  # -1 very hard ... 6 very low
        cb => sub {
            # accept client
            my $client=$socket->accept;
            panic "Couldn't connect to new wap client." and return unless $client;
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

                    my $data = $self->parseRequest($handle,(defined $self->{LOGOUT} && $self->{LOGOUT} == 1 ));
                    unless($data) {
                        undef $self->{LOGOUT};
                        $watcher->w->cancel;
                        $handle->close();
                        undef $watcher;
                        return 1;
                    }

                    undef $self->{LOGOUT}
                        if(exists $self->{LOGOUT});

                    my $WMLRootDir = sprintf('%s/%s', $self->{paths}->{HTMLDIR}, $self->{WMLRoot});
                    my $cgi = CGI->new( $data->{Query} );

                    my $console = XXV::OUTPUT::Wml->new(
                        -handle => $handle,
                        -dbh    => $self->{dbh},
                        -wmldir => $WMLRootDir,
                        -cgi    => $cgi,
                        -mime   => $mime,
                        -browser=> $data,
                        -paths  => $self->{paths},
                        -charset=> $self->{charset},
#						-start  => $self->{StartPage},
                    );

                    my $userMod = main::getModule('USER');
                    if(ref $userMod and $userMod->{active} eq 'y') {
                        $console->{USER} = $userMod->check($handle, $data->{username}, $data->{password});
                        $console->login(gettext('You are not authorized to use this system!'))
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
                            $self->handleInput($watcher, $console, $cgi);
                        } else {
                            $console->start();
                            $self->handleInput($watcher, $console, $cgi);
                            $console->footer();
                        }
                    }
                    $watcher->w->cancel;
                    undef $watcher;
                    $handle->close();
                },
            );

        },
    ) if($self->{active} eq 'y');

    return 1;

}

# ------------------
sub parseRequest {
# ------------------
    my $self = shift || return error('No object defined!');
    my $hdl = shift || return error('No handle defined!');
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
    my $self     = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
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
        return $self->usage($watcher, $console, undef, $err);
    }
}


# ------------------
sub usage {
# ------------------
    my $self = shift || return error('No object defined!');
    return main::getModule('CONFIG')->usage(@_);
}

# ------------------
sub findskins
# ------------------
{
    my $self = shift || return error('No object defined!');
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
        $self->{paths}->{HTMLDIR}
    );
    error "Couldn't find useful WML Skin at : $self->{paths}->{HTMLDIR}"
        if(scalar $found == 0);
    return $found;
}

1;
