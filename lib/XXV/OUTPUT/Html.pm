package XXV::OUTPUT::Html;

use strict;

use vars qw($AUTOLOAD);
use Locale::gettext;
use Tools;
use XXV::OUTPUT::HTML::WAIT;
use File::Path;
use File::Basename;
use File::stat;
use Fcntl;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'Html',
        Prereq => {
            'Pod::Html'  => 'Module to convert pod files to HTML ',
#           'Template'  => 'Front-end module to the Template Toolkit',
#           'Compress::Zlib'  => 'Interface to zlib compression library',
            'HTML::TextToHTML' => 'convert plain text file to HTML. ',
        },
        Description => gettext('This receives and sends HTML messages.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
    };
    return $args;
}

# ------------------
sub AUTOLOAD {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || {};
    my $params = shift || 0;

    my $name = (split('::', $AUTOLOAD))[-1];
    return  if($name eq 'DESTROY');

    my $output = $self->parseTemplate($name, $data, $params);

    $self->out( $output );
    $self->{call} = '';
}


# ------------------
sub new {
# ------------------
	my($class, %attr) = @_;
	my $self = {};
	bless($self, $class);

	# who am I
    $self->{MOD} = $self->module;

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{handle} = $attr{'-handle'}
        || return error('No handle defined!');

    $self->{paths} = $attr{'-paths'}
        || return error('No paths defined!');

    $self->{dbh} = $attr{'-dbh'}
        || return error('No dbh defined!');

    $self->{htmdir} = $attr{'-htmdir'}
        || return error('No htmdir given!');

    $self->{htmdef} = $attr{'-htmdef'}
        || return error('No htmdef given!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No cgi given!');

    $self->{mime} = $attr{'-mime'}
        || return error('No mime given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No browser given!');

    $self->{start} = $attr{'-start'}
        || return error('No start page given!');

    $self->{debug} = $attr{'-debug'}
        || 0;

    $self->{TYP} = 'HTML';

    # Forward name of Server for CGI::server_software
    $ENV{'SERVER_SOFTWARE'} = sprintf("xxvd %s",main::getVersion());
    $ENV{'SERVER_PROTOCOL'} = 'HTTP/1.1';

    eval "use Compress::Zlib";
    $self->{Zlib} = ($@ ? 0 : 1);

    &bench('CLEAR');

	return $self;
}

# ------------------
sub parseTemplate {
# ------------------
    my $self = shift || return error('No object defined!');
    my $name = shift || return error('No name defined!');
    my $data = shift || return error('No data defined!');
    my $params = shift || {};

    my $output;
    unless(defined $self->{header}) {
        $output .= $self->parseTemplateFile("start", $data, $params);
        # we must add footer on any template generated output
        $self->{inclFooter} = 1; 
    }
    $output .= $self->parseTemplateFile($name, $data, $params,((exists $self->{call}) ? $self->{call} : 'nothing'));
    return $output;
}

# ------------------
sub index {
# ------------------
    my $self = shift || return error('No object defined!');
    $self->{nopack} = 1;
    $self->{call} = 'index';
    my $params = {};
    $params->{start} = $self->{start};
    $self->out( $self->parseTemplateFile("index", {}, $params, $self->{call}));
}


# ------------------
sub parseTemplateFile {
# ------------------
    my $self = shift || return error('No object defined!');
    my $name = shift || return error ('No name defined!' );
    my $data = shift || return error ('No data defined!' );
    my $params = shift || return error ('No paramters defined!' );
    my $call = shift || 'nothing';

    $self->parseData($data)
        if($name ne 'start' && $name ne 'footer'  
        && !$self->{dontparsedData} );

    unless(exists $self->{tt}) {
      # create Template object
      $self->{tt} = Template->new(
        START_TAG    => '\<\?\%',		    # Tagstyle
        END_TAG      => '\%\?\>',		    # Tagstyle
        INCLUDE_PATH => [$self->{htmdir},$self->{htmdef}] ,  # or list ref
        INTERPOLATE  => 1,                # expand "$var" in plain text
        PRE_CHOMP    => 1,                # cleanup whitespace
        EVAL_PERL    => 1,                # evaluate Perl code blocks
      ) or return panic("Can't create instance of front-end module of Template Toolkit!");
    }

    my $u = main::getModule('USER') or return;

    # you can use two templates, first is a user defined template
    # and second the standard template
    # i.e. call the htmlhelp command the htmlhelp.tmpl
    # SpecialTemplate:  ./htmlRoot/usage.tmpl
    # StandardTemplate: ./htmlRoot/widgets/menu.tmpl
    my $widget_first  = sprintf('%s.tmpl', $call);
    my $widget_second = sprintf('widgets/%s.tmpl', $name);
    my $widget = (-e sprintf('%s/%s', $self->{htmdir}, $widget_first) ? $widget_first : $widget_second);

    my $user = ($u->{active} eq 'y' && $self->{USER}->{Name} ? $self->{USER}->{Name} : "nobody" );
    my $output;
    my $vars = {
        cgi     => $self->{cgi},
        call    => $name,
        data    => $data,
        type    => ref $data,
        info    => $self->browser,
        param   => $params,
        pid     => $$,
        debug   => $self->{debug},
        user    => $user,
        # query the current locale
        locale  => main::getGeneralConfig->{Language},
        allow   => sub{
            my($cmdobj, $cmdname, $se, $err) = $u->checkCommand($self, $_[0],"1");
            return $cmdobj;
        },

        # Deaktiviert da durch parseData alle Daten
        # komplett mit entities behandelt wurden
        entities => sub{ return $_[0] },

        # Remove entities from parameters
        reentities => sub{ return reentities($_[0]) },

        # Escape strings for javascript
        escape => sub{ 
              my $s = shift; # string
              $s =~ s/\r//g;
              $s =~ s/\n//g;
              $s =~ s/&quot;/\\&quot;/g;
              $s =~ s/\'/\\\'/g;
              return $s;
        },

        # truncate string with entities
        chop => sub{
        	my $s = shift; # string
        	my $c = shift; # count
        	my $l = shift || 0; # lines

        	if ( $c > 3 ) {
            $s = reentities($s);
            if($l)
            {
                my @text = split ('\r\n', $s);
                if(scalar @text > 1)
                {
                  my @lines;
                  foreach my $line (@text)
                  {
                    if ( length( $line ) > $c ) {
                			$line = substr( $line, 0, ( $c - 3 ) ) . '...';
                		}
                    --$l;
                    last if($l < 0);
                    push(@lines,$line);
                  }
                  $s = join("\r\n",@lines);
                } else {
                    if ( length( $s ) > ($c * $l) ) {
                			$s = substr( $s, 0, ( ($c * $l) - 3 ) ) . '...';
                		}
                }
            } 
            elsif ( length( $s ) > $c ) {
        			$s = substr( $s, 0, ( $c - 3 ) ) . '...';
        		}
          	return entities($s);
        	} else {
          	return $s ? '...' : '';
          }
        },
        url => sub{
            return url(reentities($_[0]));
        },

        # translate string, usage : gettext(foo,truncate) or gettext(foo)
        # value for truncate are optional
        gettext => sub{
            my $t = gettext($_[0]);
            $t = substr($t,0,$_[1]) . "..."
                if(defined $_[1] && length($t)>$_[1]);
            return entities($t);
        },
        version => sub{ return main::getVersion },
        loadfile    => sub{ return load_file(@_) },
        writefile   => sub{
            my $filename = shift || return error('No filename defined!');
            my $data = shift || return error('No data defined!');

            my $dir = $u->userTmp;

            # absolut Path to file
            my $file = sprintf('%s/%s', $dir, $filename);
            # absolut Path to file
            if(save_file($file, $data)) {
                # return the relative Path
                my ($relpath) = $file =~ '/(.+?/.+?)$';
                return sprintf('tempimages/%s', $filename);
            }
        },
        bench => \&bench,
        llog => sub{
            my $lines = shift || 10;
            my $lmod = main::getModule('LOGREAD');
            return $lmod->tail($self->{paths}->{LOGFILE}, $lines);
        },
        getModule => sub{
            return main::getModule(shift);
        },
    };

    $self->{tt}->process($widget, $vars, \$output)
          or return error($self->{tt}->error());

    return $output;
}

# ------------------
sub out {
# ------------------
    my $self = shift || return error('No object defined!');
    my $text = shift || 'no Text for Output';
    my $type = shift || 'text/html';
    my %args = @_;

    unless(defined $self->{header}) {
        # HTTP Header
        $self->{output_header} = $self->header($type, \%args);
    }

    $self->{output} .= $text,"\r\n"
      if($text);
}

# ------------------
sub printout {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $nopack = shift || $self->{nopack} || 0;

    if($self->{output} && $self->{handle}) {
      my $content;     
      if($self->{browser}->{Method} ne 'HEAD') {
        if(! $nopack and $self->{Zlib} and $self->{browser}->{accept_gzip}) {
          $content = Compress::Zlib::memGzip($self->{output});
        } else {
          $content = $self->{output};
        }
      }
      if($self->{output_header} && $content) {
        $self->{handle}->print($self->{output_header},$content);
        $self->{sendbytes}+= length($self->{output_header});
        $self->{sendbytes}+= length($content);
      } elsif($self->{output_header}) {
        $self->{handle}->print($self->{output_header});
        $self->{sendbytes}+= length($self->{output_header});
      } elsif($content) {
        $self->{handle}->print($content);
        $self->{sendbytes}+= length($content);
      }
      $self->{handle}->close();
    }
    undef $self->{output};
    undef $self->{output_header};
    undef $self->{nopack};
    undef $self->{hasentities};
    undef $self->{dontparsedData};
}

# ------------------
sub header {
# ------------------
    my $self = shift || return error('No object defined!');
    my $typ = shift  || 'text/html';
    my $arg = shift || {};

    $arg->{'Content-encoding'} = 'gzip'
        if($self->{browser}->{accept_gzip} && ((!defined $self->{nopack}) || $self->{nopack} == 0) );

    if(defined $self->{nocache} && $self->{nocache}) {
      $arg->{'Cache-Control'} = 'no-cache, must-revalidate' unless(defined $arg->{'Cache-Control'});
      $arg->{'Pragma'} = 'no-cache' unless(defined $arg->{'Pragma'});
    }

    $self->{header} = 200;
    return $self->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => ($typ =~ 'text/html' || (defined $self->{nocache} && $self->{nocache})) ? "now" : "+7d",
        %{$arg},
    );
}

# ------------------
sub statusmsg {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $state = shift || return error('No state defined!');
    my $msg = shift;
    my $title = shift;
    my $typ = shift || 'text/html';

    unless(defined $self->{header}) {
        $self->{nopack} = 1;

        my $s = {
            200 => '200 OK',
            204 => '204 No Response',
            301 => '301 Moved Permanently',
            302 => '302 Found',
            303 => '303 See Other',
            304 => '304 Not Modified',
            307 => '307 Temporary Redirect',
            400 => '400 Bad Request',
            401 => '401 Unauthorized',
            403 => '403 Forbidden',
            403 => '404 Not Found',
            405 => '405 Not Allowed',
            408 => '408 Request Timed Out',
            500 => '500 Internal Server Error',
            503 => '503 Service Unavailable',
            504 => '504 Gateway Timed Out',
        };
        my $status = $s->{200};
        $status = $s->{$state}
            if(exists $s->{$state});

        my $arg = {};
        $arg->{'WWW-Authenticate'} = "Basic realm=\"xxvd\""
            if($state == 401);

        $arg->{'expires'} = (($state != 304) || (defined $self->{nocache} && $self->{nocache})) ? "now" : "+7d";

        $self->{header} = $state;
        $self->{output_header} = $self->{cgi}->header(
            -type   =>  $typ,
            -status  => $status,
            %{$arg},
        );
    }
    if($msg && $title) {
        $self->{output} = $self->{cgi}->start_html(-title => $title)
                       . $self->{cgi}->h1($title)
                       . $self->{cgi}->p($msg)
                       . $self->{cgi}->end_html();
    } else {
        $self->{output} = '\r\n';
    }   
}

# ------------------
# Send HTTP Status 401 (Authorization Required)
sub login {
# ------------------
    my $self = shift || return error('No object defined!');
    my $msg = shift || '';

    $self->statusmsg(401,$msg,gettext("Authorization required"));
}

# ------------------
# Send HTTP Status 403 (Access Forbidden)
sub status403 {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $msg = shift  || '';

    $self->statusmsg(403,$msg,gettext("Forbidden"));
}


# ------------------
# Send HTTP Status 404 (File not found)
sub status404 {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $why = shift || "";

    $file =~ s/$self->{htmdir}\///g; # Don't post html root, avoid spy out

    $self->statusmsg(404,sprintf(gettext("Couldn't open file '%s' : %s!"),$file,$why),
                    gettext("Not found"));
}

# ------------------
sub question {
# ------------------
    my $self         = shift || return error('No object defined!');
    my $titel       = shift || 'undef';
    my $questions   = shift || return error ('No data defined!');
    my $erg         = shift || 0;

    my $q = $self->{cgi};
    my $quest;

    # Check Data
    if(ref $erg eq 'HASH' and ref $questions eq 'ARRAY' and exists $erg->{action}) {
        my $error;
        @$quest = @$questions;
        while (my ($name, $data) = splice(@$quest, 0, 2)) {

            $data->{typ} = 'string'
              unless($data->{typ});

            # Required value ...
            $error = $data->{req}
                if($data->{req} and not $erg->{$name});

            # Check Callback
            if(exists $data->{check} and ref $data->{check} eq 'CODE' and not $error) {
                ($erg->{$name}, $error) = $data->{check}($erg->{$name}, $data, $erg);
            }

            # Check on directory
            if($data->{typ} eq 'dir' and $data->{required} and not -d $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("Directory '%s' does not exist!"), $erg->{$name}));
            }

            # Check on file
            if($data->{typ} eq 'file' and $data->{required} and not -e $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("File '%s' does not exist!"), $erg->{$name}));
            }

            # Check on password (is not set the take the old password)
            if($data->{typ} eq 'password' and not $erg->{$name}) {
                $erg->{$name} = $data->{def};
            }

            if($error) {
                $self->err(sprintf(gettext("Error '%s' (%s) : %s!"), $data->{msg}, $name, $error));
                last;
            }
        }
        unless($error) {
            delete $erg->{action};
            return $erg;
        }
    }

    $self->formStart($titel);
    if(ref $questions eq 'ARRAY') {
        my $q = $self->{cgi};
        @$quest = @$questions;
        my $c=0;
        while (my ($name, $data) = splice(@$quest, 0, 2)) {
            my $type = delete $data->{typ};
            my $params = delete $data->{param};
            $params->{count} = $c++;
            $data->{msg} =~ s/\n/<br \/>/sig if($data->{msg});
            $data->{NAME} = '__'.$name;
            $type ||= 'string';
            $self->$type($data, $params);
        }
    } else {
        my $type = delete $questions->{typ};
        $questions->{NAME} = '__'.$type;
        $type ||= 'string';
        $self->$type($questions);
    }
    $self->formEnd;
    return undef;
}

# ------------------
sub wait {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $msg = shift  || gettext("Please wait ...");
    my $min = shift  || 0;
    my $max = shift  || 0;
    my $screen = shift  || 0;

    my $http_useragent = $self->{browser}->{http_useragent};
    if(grep(/Mozilla/i,$http_useragent) == 0  # Only Mozilla compatible browser support server push
      || grep(/MSIE/i,$http_useragent) > 0 # Stopp her for Browser e.g. Internet Explorer
      || grep(/Opera/i,$http_useragent) > 0 # Stopp her for Browser e.g. Opera
      || grep(/KHTML/i,$http_useragent) > 0) # like Safari,Konqueror
    {
        lg sprintf('Sorry, only Mozilla compatible browser support server push, this browser was identify by "%s"',
            $http_useragent );
        return 0;
    }
    $self->{nopack} = 1;
    $self->{header} = 200;
    my $waiter =  XXV::OUTPUT::HTML::WAIT->new(
        -cgi => $self->{cgi},
        -handle => $self->{handle},
        -callback => sub{
            my ($min, $max, $cur, $steps, $nextmessage, $eta) = @_;
            my $out = $self->parseTemplate(
                'wait',
                {
                    msg     => $nextmessage || $msg,
                    minimum => $min,
                    current => $cur,
                    maximum => $max,
                    steps   => $steps,
                    eta     => $eta
                },
            );
            return $out;
        },
    );

    if($max) {
        $waiter->min($min);     # Min Value for process Bar
        $waiter->max($max);     # Max Value for process Bar
        $waiter->screen($screen); # Every call of next will redraw the process bar

    }
    $waiter->next(1);

    return $waiter;
}

# ------------------
sub datei {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $typ = shift;

    my %args = ();

    my $fst = stat($file);
    unless($fst and ($fst->mode & 00400)) { # mode & S_IRUSR
      error sprintf("Couldn't stat file '%s' : %s",$file,$!);
      return $self->status404($file,$!);
    }
    my $size = $fst->size;

    $typ = $self->{mime}->{lc((split('\.', $file))[-1])}
      unless($typ);
    $typ = "application/octet-stream"
      unless($typ);

    $self->{nopack} = 1
        if($typ =~ /image\// || $typ =~ /video\//);

    # header only if caching
    $args{'ETag'} = sprintf('%x-%x-%x',$fst->ino, $size, $fst->mtime);
    return $self->statusmsg(304,undef,undef,$typ)
        if($self->{browser}->{'Match'}
            && $args{'ETag'} eq $self->{browser}->{'Match'});

    $args{'Last-Modified'} = datum($fst->mtime,'header');
    $args{'attachment'} = basename($file);
    $args{'Content-Length'} = $size
        if($self->{nopack});

    if($size > (32768 * 16)) { ## Only files bigger then 512k
        lg sprintf("stream file : '%s' (%s)",$file,convert($size));
        $self->_stream([$file],$size, 0, $typ, %args);
    } else {
        my $data = load_file($file) || '';
        # send data
        $self->out($data, $typ, %args );
    }
}

# ------------------
sub stream {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $files = shift || return error('No file defined!');
    my $typ = shift;
    my $offset = shift || 0;

    my %args = ();
    my $total = 0;

    foreach my $file (@{$files}) {

      my $fst = stat($file);
      unless($fst and ($fst->mode & 00400)) { # mode & S_IRUSR
        error sprintf("Couldn't stat file '%s' : %s",$file,$!);
        return $self->status404($file,$!);
      }
      $total += $fst->size;
    }
    $args{'Content-Length'} = ($total - $offset);

    return $self->_stream($files, $total, $offset, $typ, %args);
}

sub _stream {
    my $self = shift  || return error('No object defined!');
    my $files = shift || return error('No file defined!');
    my $size = shift;
    my $offset = shift || 0;
    my $typ = shift;
    my %args = @_;

    $self->{nopack} = 1;
    my $handle = $self->{handle};

    my $child = fork(); 
    if ($child < 0) {
      error("Couldn't create process for streaming : " . $!);
      my $file = join(',',@$files);
      return $self->status404($file,$!);
    }
    elsif ($child > 0) {
      $self->{header} = 200;
      $self->{sendbytes} += $size;
      undef $self->{handle};
      undef $self->{output};
      return 1;
    }
    elsif ($child == 0) {
      eval 
      { 
        local $SIG{'__DIE__'};

        my $hdr = $self->header($typ, \%args);
        if($self->{browser}->{Method} eq 'HEAD') {
          $handle->print($hdr);
        } else {
          foreach my $file (@{$files}) {
            my $r = 0;
            if(sysopen( FH, $file, O_RDONLY|O_BINARY )) {
              binmode FH;

              if($hdr) {
                $handle->print($hdr);
                $hdr = undef;

                if($offset && $offset != sysseek(FH,$offset,0)) { #SEEK_SET
                  error(sprintf("Can't seek file '%s': %s",$file,$!));
                }
              }
              my $bytes;
              my $data;
              do {
                $r = 0;
                $bytes = sysread( FH, $data, 4096 );
                if($bytes) {
                  my $peer = $handle->peername;
                  $r = $handle->send($data,0,$peer) 
                    if($peer);
                }
              } while $r && $bytes > 0;
              close(FH);
            } else {
              error sprintf("Could not open file '%s'! : %s", $file,$!);
            }
          }
        }
        $handle->close();
      };
      error($@) if $@;
      exit 0;
    }
    return 0;
}

# ------------------
sub image {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $typ = shift;
    return $self->datei($file,$typ);
}

# ------------------
sub pod {
# ------------------
    my $self = shift || return error('No object defined!');
    my $modname = uc(shift) || return error ('No modul defined!');
    $modname = ucfirst($modname) if($modname eq 'GENERAL');

    my $podfile = sprintf('%s/%s.pod', $self->{paths}->{PODPATH}, $modname);
    return $self->err(gettext('Module %s not found!'), $modname)
        unless(-r $podfile);

    my $u = main::getModule('USER');
    my $tmpdir = $u->userTmp;
    my $outfile = sprintf('%s/%s_%d.pod', $tmpdir, $modname, time);

    pod2html(
        "--cachedir=$tmpdir",
        "--infile=$podfile",
        "--outfile=$outfile",
    );
    return error('Problem to convert pod2html')
        unless(-r $outfile);

    my $html = load_file($outfile);
    $html = $1 if($html =~ /\<body.*?\>(.+?)\<\/body\>/si);
    $self->link({
        text => gettext("Back to configuration page."),
        url => $self->{browser}->{Referer},
    });

    $self->message($html);
}

# ------------------
sub txtfile {
# ------------------
    my $self = shift || return error('No object defined!');
    my $filename = shift || return error ('No file defined!');
    my $param = shift || {};

    my $txtfile = sprintf('%s/%s', $self->{paths}->{DOCPATH}, $filename);
    unless( -r $txtfile) {
      $txtfile = sprintf('%s/%s.txt', $self->{paths}->{DOCPATH}, $filename);
      unless( -r $txtfile) {
        my $gzfile  = sprintf('%s/%s.gz', $self->{paths}->{DOCPATH}, $filename);
        unless( -r $gzfile) {
          $gzfile  = sprintf('%s/%s.txt.gz', $self->{paths}->{DOCPATH}, $filename);
          unless( -r $gzfile) {
            my $e = $!;
            error sprintf("Could not open file '%s/%s[.txt .gz txt.gz]! : %s", $self->{paths}->{DOCPATH}, $filename, $e);
            return $self->err(sprintf(gettext("Could not open file '%s'! : %s"), $filename, $e));
          }
        }
        $txtfile = main::getModule('HTTPD')->unzip($gzfile);
      }
    }

    my $topic = gettext("File");

    if($param->{'format'} eq 'txt') {
        my $txt = load_file($txtfile);
        return $self->message($txt, {tags => {first => "$topic: $filename"}});
    }

    my $u = main::getModule('USER');
    my $htmlfile = sprintf('%s/temp_txt.html', $u->userTmp);

    # create TextToHTML object
    unless(exists $self->{txt2html}) {
      $self->{txt2html} = HTML::TextToHTML->new(
          preformat_whitespace_min => 4,
      );
    }

    $self->{txt2html}->txt2html(
                     infile=>[$txtfile],
                     outfile=>$htmlfile,
                     title=> $filename,
                     mail=>1,
    );
    my $html = load_file($htmlfile);
    $html = $1 if($html =~ /\<body.*?\>(.+?)\<\/body\>/si);
    $self->message($html, {tags => {first => "<h1>$topic: $filename</h1>"}});
}

# ------------------
sub typ {
# ------------------
    my $self = shift || return error('No object defined!');
    return $self->{TYP};
}

# ------------------
sub setCall {
# ------------------
    my $self = shift || return error('No object defined!');
    my $name = shift || return error ('No name defined!');

    $self->{call} = $name;
    return $self->{call};
}

# ------------------
sub browser {
# ------------------
    my $self = shift || return error('No object defined!');
    return $self->{browser};
}

# Special Version from Message (with error handling)
# ------------------
sub msg {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $data = shift || 0;
    my $err = shift  || 0;

    unless($err) {
        $self->message($data);
    } else {
        $self->err($data || $err);
        return undef;
    }
}

# ------------------
sub parseData {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $dta = shift  || return '';

    if(ref $dta eq 'HASH') {
        foreach my $name (keys %$dta) {
            if(ref $dta->{$name}) {
                $self->parseData($dta->{$name});
            } else {
                $dta->{$name} = reentities($dta->{$name}) if($self->{hasentities});
                $dta->{$name} = entities($dta->{$name});
            }
        }
    } elsif (ref $dta eq 'ARRAY') {
        foreach (@$dta) {
            if(ref $_) {
                $self->parseData($_);
            } else {
                $_ = reentities($_) if($self->{hasentities});
                $_ = entities($_);
            }
        }
    }
    $self->{hasentities} = 1;
    return $dta;
}


1;
