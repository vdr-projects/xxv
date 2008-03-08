package XXV::MODULES::HTTPD;

use XXV::OUTPUT::Html;
use XXV::OUTPUT::Ajax;
use File::Basename;
use File::Find;

use Tools;

$| = 1;

use strict;

my $mime = {
    htm  => ["text/html",               '',      ''],
    html => ["text/html",               '',      ''],
    png  => ["image/png",               'nopack','attachment'],
    gif  => ["image/gif",               'nopack','attachment'],
    jpg  => ["image/jpeg",              'nopack','attachment'],
    css  => ["text/css",                ''      ,'attachment'],
    ico  => ["image/x-icon",            'nopack','attachment'],
    js   => ["application/x-javascript",''      ,'attachment'],
    m3u  => ["audio/x-mpegurl",         'nopack','attachment'],
    mp3  => ["audio/x-mp3",             'nopack','attachment'],
    wav  => ["audio/x-wav",             'nopack','attachment'],
    ogg  => ["application/x-ogg",       'nopack','attachment'],
    rss  => ["application/xhtml+xml",   '',      'attachment'],
    avi  => ["video/avi",               'nopack','attachment'],
    mp4  => ["video/mp4",               'nopack','attachment'],
    mpg  => ["video/x-mpeg",            'nopack','attachment'],
    mpeg => ["video/x-mpeg",            'nopack','attachment'],
    mov  => ["video/quicktime",         'nopack','attachment'],
    wmv  => ["video/x-ms-wmv",          'nopack','attachment'],
    flv  => ["video/x-flv",             'nopack','attachment']
};

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'HTTPD',
        Prereq => {
            'IO::Socket::INET'  => 'Object interface for AF_INET domain sockets ',
            'MIME::Base64'      => 'Encoding and decoding of base64 strings',
            'CGI qw/:push -nph -no_xhtml -compile/'
                                => 'Simple Common Gateway Interface Class',
            'Compress::Zlib'    => 'Interface to zlib compression library. ',
        },
        Description => gettext('This module is a multisession HTTPD server.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $self->status(@_) },
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
                description => gettext('Number of port to listen for http clients'),
                default     => 8080,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            Interface => {
                description => gettext('Local interface to bind service'),
                default     => '0.0.0.0',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            HtmlRoot => {
                description => gettext('Skin used'),
                default     => 'default',
                type        => 'list',
                required    => gettext('This is required!'),
                choices     => sub{ return $self->findskins },
            },
            StartPage => {
                description => gettext('Startup screen'),
                default     => 'now',
                type        => 'list',
                required    => gettext('This is required!'),
                choices     => [
                    [ gettext('Schema'),          'schema'],
                    [ gettext('Running now'),     'now'],
                    [ gettext('Program guide'),   'program'],
                    [ gettext('Autotimer'),       'alist'],
                    [ gettext('Timers'),          'tlist'],
                    [ gettext('Recordings'),      'rlist'],
                    [ gettext('Music'),           'mlist'],
                    [ gettext('Remote'),          'remote'],
                    [ gettext('Teletext'),        'vtxpage'],
                    [ gettext('Status'),          'sa'],
                ],
            },
            Debug => {
                description => gettext('Dump additional debugging information, required only for software development.'),
                default     => 'n',
                type        => 'confirm',
            },
        },
        Commands => {
            checkvalue => {
                hidden      => 'yes',
                callback    => sub{ $self->checkvalue(@_) },
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

    $self->{charset} = delete $attr{'-charset'};

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
    $self->init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $self = shift || return error('No object defined!');

    # globals
    my $channels;

    $self->{STATUS}->{'starttime'} = time;

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
            panic "Couldn't connect to new http client." and return unless $client;
            $client->autoflush;

            # make "channel" number
            my $channel=++$channels;

            $self->{STATUS}->{'connects'}++;

            # install a communicator
            Event->io(
                fd => $client,
                prio => -1,  # -1 very hard ... 6 very low
                poll => 'r',
                cb => sub {
                    my $watcher = shift;
                    $self->communicator($watcher);
                    }
            );
        },
    ) if($self->{active} eq 'y');

    return 1;
}

sub communicator {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');

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

    my $ip = getip($handle);
    my $htmlRootDir = sprintf('%s/%s', $self->{paths}->{HTMLDIR}, $self->{HtmlRoot});
		my $htmlDefDir = sprintf('%s/%s', $self->{paths}->{HTMLDIR}, 'default');

    my $query = $data->{Query};                     
    if($data->{Method} eq 'POST' && $data->{Post}) {
      $query .= '&' if($query);
      $query .= $data->{Post};
    } 
    my $cgi = CGI->new( $query );

    my $console;
    if(my $outputtype = $cgi->param('ajax')) {
        # Is a Ajax Request
        $console = XXV::OUTPUT::Ajax->new(
            -handle => $handle,
            -cgi    => $cgi,
            -browser=> $data,
            -output => $outputtype,
            -debug  => ($self->{Debug} eq 'y' ? 1 : 0),
            -charset=> $self->{charset},
        );
    } else {
        # Is a Html Request
        $console = XXV::OUTPUT::Html->new(
            -handle => $handle,
            -dbh    => $self->{dbh},
            -htmdir => $htmlRootDir,
						-htmdef => $htmlDefDir,
            -cgi    => $cgi,
            -mime   => $mime,
            -browser=> $data,
            -paths  => $self->{paths},
            -start  => $self->{StartPage},
            -debug  => ($self->{Debug} eq 'y' ? 1 : 0),
            -charset=> $self->{charset},
        );
    }

    my $userMod = main::getModule('USER');
    if(ref $userMod and $userMod->{active} eq 'y') {
        $console->{USER} = $userMod->check($handle, $data->{username}, $data->{password});
        $console->login(gettext('You are not authorized to use this system!'))
            unless(exists $console->{USER}->{Level});
    }

    if(ref $userMod and
            ($userMod->{active} ne 'y'
                or exists $console->{USER}->{Level})) {

        $console->setCall('nothing');
        if(not $data->{Query} and 
              ($data->{Request} eq '/' or -d sprintf('%s/%s', $htmlRootDir,$data->{Request}))) {
            my $request = $htmlRootDir;
            $request .= '/';
            $request .= $data->{Request};
            $request .= '/';
            $request =~ s/\.\.\///g;
            $request =~ s/\/\.\.//g;
            $request =~ s/\/+/\//g;
            # Send the first page (index.html)
            if(-r sprintf('%sindex.tmpl', $request)) {
                $console->index;
            } else {
                $console->datei(sprintf('%sindex.html', $request));
            }
        } elsif(my $typ = $mime->{lc((split('\.', $data->{Request}))[-1])}) {
            # Send multimedia files (this must registered in $mime!)
            my $request = $data->{Request};
            $request =~ s/\.\.\///g;
            $request =~ s/\/\.\.//g;
            $request =~ s/\/+/\//g;
            if($request =~ /epgimages\//) {
                my $epgMod = main::getModule('EPG');
                if($epgMod) {
                  $request =~ s/.*epgimages\//$epgMod->{epgimages}\//;
                  $console->datei($request, $typ);
                } else {
                  $self->ModulNotLoaded($console,'EPG');
                }
            } elsif($request =~ /tempimages\//) {
                my $tmp = $userMod->userTmp;
                $request =~ s/.*tempimages\//$tmp\//;
                $console->datei($request, $typ);
            } else {
                $console->datei($htmlRootDir . $request, $typ);
            }
        } else {
            $self->handleInput($watcher, $console, $cgi);
        }

    } else {
      $self->ModulNotLoaded($console,'USER');
    }
    $console->footer() if($console->{inclFooter});
    $console->printout();

    # make entry more readable
		$data->{Query} =~ s/%([a-f0-9][a-f0-9])/pack("C", hex($1))/ieg 
      if($data->{Query});
		$data->{Referer} =~ s/%([a-f0-9][a-f0-9])/pack("C", hex($1))/ieg
      if($data->{Referer});
    # Log like Apache Format ip, resolved hostname, user, method request, status, bytes, referer, useragent
    lg sprintf('%s - %s "%s %s%s" %s %s "%s" "%s"',
          $ip,
          $data->{username} ? $data->{username} : "-",
          $data->{Method},
          $data->{Request} ? $data->{Request} : "",
          $data->{Query} ? "?" . $data->{Query} : "",
          $console->{'header'},
          $console->{'sendbytes'},
          $data->{Referer} ? $data->{Referer} : "-",
          "-" #$data->{http_useragent} ? $data->{http_useragent} : ""
        );

    $self->{STATUS}->{'sendbytes'} += $console->{'sendbytes'};

    $watcher->w->cancel;
    undef $watcher;
}

# ------------------
sub _readline {
# ------------------
    my $fh = $_[0];
    my $c='';
    my $line='';
    my $eof=0;

    while ($c ne "\n" && ! $eof) {
    	if (sysread($fh, $c, 1) > 0) {
        $line = $line . $c;
      } else {
        $eof=1;
      }
    }
    return $line;
}
# ------------------
sub parseRequest {
# ------------------
    my $self = shift || return error('No object defined!');
    my $socket = shift || return error('No handle defined!');
    my $logout = shift || 0;

    binmode $socket;
   	my $data = {};
    my $line;
    while (defined($line = &_readline($socket))) {
        if(!$line || $line eq "\r\n") {
    			last;
        } elsif(!$data->{Method} && $line =~ /^(\w+) (\/[\w\.\/\-\:\%]*)([\?[\w=&\.\+\%-\:\!]*]*)[\#\d ]+HTTP\/1.\d/) {
    			($data->{Method}, $data->{Request}, $data->{Query}) = ($1, $2, $3 ? substr($3, 1, length($3)) : undef);
        } elsif($line =~ /Referer: (.*)/) {
    			$data->{Referer} = $1;
    	  	$data->{Referer} =~ s/(\r|\n)//g;
    		} elsif($line =~ /Host: (.*)/) {
    			$data->{HOST} = $1;
    	  	$data->{HOST} =~ s/(\r|\n)//g;
    		} elsif($line =~ /Authorization: basic (.*)/i and not $logout) {
    			($data->{username}, $data->{password}) = split(":", MIME::Base64::decode_base64($1), 2);
    		} elsif($line =~ /User-Agent: (.*)/i) {
    			$data->{http_useragent} = $1;
    	  	$data->{http_useragent} =~ s/(\r|\n)//g;
    		} elsif($line =~ /Accept-Encoding:.+?gzip/i) {
    			$data->{accept_gzip} = 1;
    		} elsif($line =~ /If-None-Match: (\S+)/i) {
    			$data->{Match} = $1;
    		} elsif($line =~ /Cookie: (\S+)=(\S+)/i) {
    			$data->{$1} = $2;
    		} elsif($line =~ /Content-Type: (\S+)/i) {
    			$data->{ContentType} = $1;
    		} elsif($line =~ /Content-Length: (\S+)/i) {
    			$data->{ContentLength} = $1;
    		} else {
          #dumper($line);
    		}
        $self->{STATUS}->{'readbytes'} += length($line);
      }
   
	$data->{Request} =~ s/%([a-f0-9][a-f0-9])/pack("C", hex($1))/ieg
    if($data->{Request});
  if($data->{Method}) {
    if($data->{Method} eq 'GET' 
      or $data->{Method} eq 'HEAD') {
      #dumper($data);
      return $data;
    } elsif($data->{Method} eq 'POST') {
      if(int($data->{ContentLength})>0) {
        my $post;
        my $bytes = sysread($socket,$post,$data->{ContentLength});
        $data->{Post} = $post
          if($bytes && $data->{ContentLength} == $bytes);
        $self->{STATUS}->{'readbytes'} += $bytes;
      }
      #dumper($data);
      return $data;
    } else {
      lg sprintf("Unsupported HTTP Method : %s",$data->{Method});
    }
  }
  return undef;
}
# ------------------
sub ModulNotLoaded {
# ------------------
    my $self     = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $module = shift || return error('No module defined!');

    $console->statusmsg(500,
          ,sprintf(gettext("Module '%s' is'nt loaded!"),$module),
          ,gettext("Internal Server Error"));
}

# ------------------
sub handleInput {
# ------------------
    my $self     = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $cgi     = shift || return error('No CGI object defined!');

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
    if($u) {
      my ($cmdobj, $cmdname, $shorterr, $err) = $u->checkCommand($console, $ucmd);
      $console->setCall($cmdname);
      if($cmdobj and not $shorterr) {

          if($cmdobj->{binary}) {
            $console->{nocache} = 1 
                if($cmdobj->{binary} eq 'nocache');
          }
          $cmdobj->{callback}($watcher, $console, $udata, $result );
      } elsif($shorterr eq 'noperm' or $shorterr eq 'noactive') {
          $console->status403($err);
      } else {
          $self->usage($watcher, $console, undef, $err);
      } 
    } else {
      $self->ModulNotLoaded($console,'USER');
    }
}

# ------------------
sub usage {
# ------------------
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $modulename = shift;
    my $hint = shift;

    my $m = main::getModule('CONFIG');
    if ($m){
      return $m->usage($watcher,$console,$modulename,$hint);
    } else {
      $self->ModulNotLoaded($console,'CONFIG');
    }

}

# ------------------
sub status {
# ------------------
    my $self = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift || return;
    my $lastReportTime = shift || 0;

    return {
        message => sprintf(gettext('Traffic on HTTPD socket since %s: transmitted: %s - received: %s - connections: %d.'),
            datum($self->{STATUS}->{'starttime'}), 
            convert($self->{STATUS}->{'sendbytes'}), 
            convert($self->{STATUS}->{'readbytes'}),
            $self->{STATUS}->{'connects'} ),
    };

}

# ------------------
sub findskins
# ------------------
{
    my $self = shift || return error('No object defined!');
    my $found;
    find({ wanted => sub{
              if(-d $File::Find::name
                    and ( -e $File::Find::name.'/index.tmpl'
                      or  -e $File::Find::name.'/index.html')
              ) {
                    my $l = basename($File::Find::name);
                    push(@{$found},[$l,$l]);
                }
           },
           follow => 1,
           follow_skip => 2,
        },
        $self->{paths}->{HTMLDIR}
    );
    error "Couldn't find useful HTML Skin at : $self->{paths}->{HTMLDIR}"
        if(scalar $found == 0);
    return sort { lc($a->[0]) cmp lc($b->[0]) } @{$found};
}

# ------ unzip ------------
# Name: unzip
# Desc: Uncompress Files in gz format
# Usag: my $res = $self->unzip(file.gz);
# Test: my $res = $self->unzip('t/abc.gz');
#       return 1 if(load_file($res) eq 'abc');
# ------ unzip ------------
sub unzip {
    my $self  = shift || return error('No object defined!');
    my $file = shift || return error('No file defined!');

    my $gz = gzopen($file, "rb")
         or return $self->msg(undef, sprintf(gettext("Could not open file '%s'! : %s"), $file, &gzerror ));

    my $text;
    while($gz->gzread(my $buffer) > 0) {
        $text .= $buffer; # nothing
    }

    $gz->gzclose();
    my $u = main::getModule('USER');
    if($u) {
      my $tmpfile = sprintf('%s/gz_%d.tmp', $u->userTmp, time);
      return save_file($tmpfile, $text);
    }
}


# ------------------
# Callback for ajax, to check for right values in HTML Widget
# supported :
# isdir:/tmp
# isfile:/bla/foobar
# getip:localhost
sub checkvalue {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return error('No data defined!');

    my @query = split(':',$data);
    my $check = $query[0];
    shift @query;
    my $value = join(':',@query);

    my $erg;
    my $iserror;
    # e.g. isdir:/tmp
    if($check eq "isdir") {
      if(-d $value) {
        $erg = gettext("Directory found.");
      } else {
        $erg = gettext("Directory not found.");
        $iserror = 1;
      }
    # e.g. isfile:/bla/foobar
    } elsif($check eq "isfile") {
      if(-r $value) {
        $erg = gettext("File found.");
      } else {
        $erg = gettext("File not found.");
        $iserror = 1;
      }
    # e.g. getip:localhost
    } elsif($check eq "getip") {
      my $aton = inet_aton($value);
      if($aton) {
        $erg = inet_ntoa($aton);
      } else {
        $erg = gettext("Host does not exist.");
        $iserror = 1;
      }
    # Unknown query
    } else {
      $erg = sprintf(gettext("Query : '%s' not supported."),$check);
      $iserror = 1;
    }

    return $console->msg($erg, $iserror)
        if(ref $console);
}


1;
