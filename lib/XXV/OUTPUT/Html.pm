package XXV::OUTPUT::Html;

use strict;

#use Template;
use vars qw($AUTOLOAD);
use Locale::gettext;
use Tools;
use XXV::OUTPUT::HTML::WAIT;
use File::Path;
use File::Basename;
use Pod::Html;
use Fcntl;
#use Thread;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'Html',
        Prereq => {
            'HTML::TextToHTML' => 'convert plain text file to HTML. ',
        },
        Description => gettext('This receive and send HTML messages.'),
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
    my $obj = shift || return error ('No Object!' );
    my $data = shift || {};
    my $params = shift || 0;

    my $name = (split('::', $AUTOLOAD))[-1];
    return  if($name eq 'DESTROY');

    my $output = $obj->parseTemplate($name, $data, $params);

    $obj->out( $output );

    $obj->{call} = '';
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
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{handle} = $attr{'-handle'}
        || return error('No handle defined!');

    $self->{paths} = $attr{'-paths'}
        || return error('No Paths defined!');

    $self->{dbh} = $attr{'-dbh'}
        || return error('No DBH defined!');

    $self->{htmdir} = $attr{'-htmdir'}
        || return error('No htmdir given!');

    $self->{htmdef} = $attr{'-htmdef'}
        || return error('No htmdef given!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No TemplateDir given!');

    $self->{mime} = $attr{'-mime'}
        || return error('No Mimehash given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No Mimehash given!');

    $self->{start} = $attr{'-start'}
        || return error('No StartPage given!');

    $self->{debug} = $attr{'-debug'}
        || 0;

    $self->{TYP} = 'HTML';

    # Forward name of Server for CGI::server_software
    $ENV{'SERVER_SOFTWARE'} = sprintf("xxvd %s",main::getVersion());
    $ENV{'SERVER_PROTOCOL'} = 'HTTP/1.1';

    # create Template object
    $self->{tt} = Template->new(
      START_TAG    => '\<\?\%',		    # Tagstyle
      END_TAG      => '\%\?\>',		    # Tagstyle
      INCLUDE_PATH => [$self->{htmdir},$self->{htmdef}] ,  # or list ref
      INTERPOLATE  => 1,                # expand "$var" in plain text
      PRE_CHOMP    => 1,                # cleanup whitespace
      EVAL_PERL    => 1,                # evaluate Perl code blocks
    );

    eval "use Compress::Zlib";
    $self->{Zlib} = ($@ ? 0 : 1);


    # create TextToHTML object
    $self->{txt2html} = HTML::TextToHTML->new(
        preformat_whitespace_min => 4,
    );

    &bench('CLEAR');

	return $self;
}

# ------------------
sub parseTemplate {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return error ('No Name!' );
    my $data = shift || return error ('No Data!' );
    my $params = shift || {};

    my $output;
    unless(defined $obj->{header}) {
        $output .= $obj->parseTemplateFile("start", $data, $params);
    }
    $output .= $obj->parseTemplateFile($name, $data, $params,((exists $obj->{call}) ? $obj->{call} : 'nothing'));
    return $output;
}

# ------------------
sub index {
# ------------------
    my $obj = shift || return error ('No Object!' );
    $obj->{nopack} = 1;
    $obj->{call} = 'index';
    my $params = {};
    $params->{start} = $obj->{start};
    $obj->out( $obj->parseTemplateFile("index", {}, $params, $obj->{call}));
}


# ------------------
sub parseTemplateFile {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return error ('No Name!' );
    my $data = shift || return error ('No Data!' );
    my $params = shift || return error ('No params!' );
    my $call = shift || 'nothing';

    $obj->parseData($data)
        if($name ne 'start' && $name ne 'footer'  
        && !$obj->{dontparsedData} );

    my $t = $obj->{tt};
    my $u = main::getModule('USER');

    # you can use two templates, first is a user defined template
    # and second the standard template
    # i.e. call the htmlhelp command the htmlhelp.tmpl
    # SpecialTemplate:  ./htmlRoot/usage.tmpl
    # StandardTemplate: ./htmlRoot/widgets/menu.tmpl
    my $widget_first  = sprintf('%s.tmpl', $call);
    my $widget_second = sprintf('widgets/%s.tmpl', $name);
    my $widget = (-e sprintf('%s/%s', $obj->{htmdir}, $widget_first) ? $widget_first : $widget_second);

    my $user = ($u->{active} eq 'y' && $obj->{USER}->{Name} ? $obj->{USER}->{Name} : "nobody" );
    my $output;
    my $vars = {
        cgi     => $obj->{cgi},
        call    => $name,
        data    => $data,
        type    => ref $data,
        info    => $obj->browser,
        param   => $params,
        pid     => $$,
        debug   => $obj->{debug},
        user    => $user,
        # query the current locale
        locale  => main::getGeneralConfig->{Language},
        allow   => sub{
            my($cmdobj, $cmdname, $se, $err) = $u->checkCommand($obj, $_[0],"1");
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
        url     => sub{
            	my $s = shift; # string
              $s = reentities($s);
              $s  =~ s/([^a-z0-9A-Z])/sprintf('%%%X', ord($1))/seg;
              return $s;
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
            my $filename = shift || return error('No Filename to write');
            my $data = shift || return error('Nothing data to write');

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
        fmttime => sub{ return fmttime(@_) },
        bench => \&bench,
        llog => sub{
            my $lines = shift || 10;
            my $lmod = main::getModule('LOGREAD');
            return $lmod->tail($obj->{paths}->{LOGFILE}, $lines);
        },
        getModule => sub{
            return main::getModule(shift);
        },
    };

    $t->process($widget, $vars, \$output)
          or return error($t->error());

    return $output;
}

# ------------------
sub out {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $text = shift || 'no Text for Output';
    my $type = shift || 'text/html';
    my %args = @_;

    unless(defined $obj->{header}) {
        # HTTP Header
        $obj->{output_header} = $obj->header($type, \%args);
    }

    $obj->{output} .= $text,"\r\n"
      if($text);
}

# ------------------
sub printout {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $nopack = shift || $obj->{nopack} || 0;

    if($obj->{output} && $obj->{handle}) {
      my $content = $obj->{output};

      $content = Compress::Zlib::memGzip($content)
          if(! $nopack and $obj->{Zlib} and $obj->{browser}->{accept_gzip});

      $obj->{handle}->print($obj->{output_header}, $content);
      $obj->{sendbytes}+= length($obj->{output_header});
      $obj->{sendbytes}+= length($content);
      $obj->{handle}->close();
    }
    undef $obj->{output};
    undef $obj->{output_header};
    undef $obj->{nopack};
    undef $obj->{hasentities};
    undef $obj->{dontparsedData};
}

# ------------------
sub getType {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $typ = shift  || 'text/html';

    my $typefile = sprintf('%s/%s', $obj->{htmdir}, 'GENERICTYP');
    if(-e $typefile and -r $typefile) {
        $typ = load_file($typefile);
        $typ =~ s/[\r|\n]//sig;
    }
    return $typ;
}

# ------------------
sub header {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $typ = $obj->getType(shift) || return error ('No Type!' );
    my $arg = shift || {};

    $arg->{'Content-encoding'} = 'gzip'
        if($obj->{browser}->{accept_gzip} && ((!defined $obj->{nopack}) || $obj->{nopack} == 0) );

    if(defined $obj->{nocache} && $obj->{nocache}) {
      $arg->{'Cache-Control'} = 'no-cache, must-revalidate' if(!defined $arg->{'Cache-Control'});
      $arg->{'Pragma'} = 'no-cache' if(!defined $arg->{'Pragma'});
    }

    $obj->{header} = 200;
    return $obj->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => ($typ =~ 'text/html' || (defined $obj->{nocache} && $obj->{nocache})) ? "now" : "+7d",
        %{$arg},
    );
}

# ------------------
sub statusmsg {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $state = shift || return error ('No Status!');
    my $msg = shift;
    my $title = shift;

    unless(defined $obj->{header}) {
        $obj->{nopack} = 1;

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

        $arg->{'expires'} = "now"
            if($state != 304);

        $obj->{header} = $state;
        $obj->{output_header} = $obj->{cgi}->header(
            -type   =>  'text/html',
            -status  => $status,
            %{$arg},
        );
    }
    if($msg && $title) {
        $obj->{output} = $obj->{cgi}->start_html(-title => $title)
                       . $obj->{cgi}->h1($title)
                       . $obj->{cgi}->p($msg)
                       . $obj->{cgi}->end_html();
    } else {
        $obj->{output} = '\r\n';
    }   
}

# ------------------
# Send HTTP Status 401 (Authorization Required)
sub login {
# ------------------
    my $obj = shift || return error ('No Object!');
    my $msg = shift || '';

    $obj->statusmsg(401,$msg,gettext("Authorization required"));
}

# ------------------
# Send HTTP Status 403 (Access Forbidden)
sub status403 {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $msg = shift  || '';

    $obj->statusmsg(403,$msg,gettext("Forbidden"));
}


# ------------------
# Send HTTP Status 404 (File not found)
sub status404 {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $file = shift || return error ('No File!');
    my $why = shift || "";

    $file =~ s/$obj->{htmdir}\///g; # Don't post html root, avoid spy out

    $obj->statusmsg(404,sprintf(gettext("Can't open file '%s' : %s"),$file,$why),
                    gettext("Not found"));
}

# ------------------
sub question {
# ------------------
    my $obj         = shift || return error ('No Object!' );
    my $titel       = shift || 'undef';
    my $questions   = shift || return error ('No Data!' );
    my $erg         = shift || 0;

    my $q = $obj->{cgi};
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
                ($erg->{$name}, $error) = (undef, sprintf(gettext("Directory '%s' is doesn't exist!"), $erg->{$name}));
            }

            # Check on file
            if($data->{typ} eq 'file' and $data->{required} and not -e $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("File '%s' is doesn't exist!"), $erg->{$name}));
            }

            # Check on password (is not set the take the old password)
            if($data->{typ} eq 'password' and not $erg->{$name}) {
                $erg->{$name} = $data->{def};
            }

            if($error) {
                $obj->err(sprintf(gettext("Error at field '%s' (%s) : %s"), $data->{msg}, $name, $error));
                last;
            }
        }
        unless($error) {
            delete $erg->{action};
            return $erg;
        }
    }

    $obj->formStart($titel);
    if(ref $questions eq 'ARRAY') {
        my $q = $obj->{cgi};
        @$quest = @$questions;
        my $c=0;
        while (my ($name, $data) = splice(@$quest, 0, 2)) {
            my $type = delete $data->{typ};
            my $params = delete $data->{param};
            $params->{count} = $c++;
            $data->{msg} =~ s/\n/<br \/>/sig if($data->{msg});
            $data->{NAME} = '__'.$name;
            $type ||= 'string';
            $obj->$type($data, $params);
        }
    } else {
        my $type = delete $questions->{typ};
        $questions->{NAME} = '__'.$type;
        $type ||= 'string';
        $obj->$type($questions);
    }
    $obj->formEnd;
    return undef;
}

# ------------------
sub wait {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $msg = shift  || gettext("Please wait ...");
    my $min = shift  || 0;
    my $max = shift  || 0;
    my $screen = shift  || 0;

    my $http_useragent = $obj->{browser}->{http_useragent};
    if(grep(/Mozilla/i,$http_useragent) == 0  # Only Mozilla compatible browser support server push
      || grep(/MSIE/i,$http_useragent) > 0 # Stopp her for Browser e.g. Internet Explorer
      || grep(/Opera/i,$http_useragent) > 0 # Stopp her for Browser e.g. Opera
      || grep(/KHTML/i,$http_useragent) > 0) # like Safari,Konqueror
    {
        lg sprintf('Sorry, only Mozilla compatible browser support server push, this browser was identify by "%s"',
            $http_useragent );
        return 0;
    }
    $obj->{nopack} = 1;
    $obj->{header} = 200;
    my $waiter =  XXV::OUTPUT::HTML::WAIT->new(
        -cgi => $obj->{cgi},
        -handle => $obj->{handle},
        -callback => sub{
            my ($min, $max, $cur, $steps, $nextmessage, $eta) = @_;
            my $out = $obj->parseTemplate(
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
    my $obj = shift  || return error ('No Object!' );
    my $file = shift || return error ('No File!');
    my $typ = shift;

    my %args = ();

    return $obj->status404($file,$!)
      if(!-r $file);

    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
       	             $atime,$mtime,$ctime,$blksize,$blocks) = stat $file;
    return $obj->status404($file,$!)
      if(!$blocks);

    # header only if caching
    $args{'ETag'} = sprintf('%x-%x-%x',$ino, $size, $mtime);
    return $obj->statusmsg(304)
        if($obj->{browser}->{'Match'}
            && $args{'ETag'} eq $obj->{browser}->{'Match'});
        
    $typ = $obj->{mime}->{lc((split('\.', $file))[-1])}
      if(!$typ);
    $typ = "application/octet-stream"
      if(!$typ);

    $obj->{nopack} = 1
        if($typ =~ /image\// || $typ =~ /video\//);

    my(@MON)=qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
    my(@WDAY) = qw/Sun Mon Tue Wed Thu Fri Sat/;
    my($sec,$min,$hour,$mday,$mon,$year,$wday) = gmtime($mtime);
    $args{'Last-Modified'} = sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
                   $WDAY[$wday],$mday,$MON[$mon],$year + 1900,$hour,$min,$sec);
    $args{'attachment'} = basename($file);
    $args{'Content-Length'} = $size
        if($obj->{nopack});

    if($size > (32768 * 16)) { ## Only files bigger then 512k

      lg sprintf("stream file : '%s' (%s)",$file,convert($size));

      $obj->{nopack} = 1;
      my $handle = $obj->{handle};

      my $child = fork(); 
      if ($child < 0) {
        error("Can't create process for streaming : " . $!);
        return $obj->status404($file,$!);
      }
      elsif ($child > 0) {
        $obj->{sendbytes} += $size;
      }
      elsif ($child == 0) {

        eval 
        { 
          local $SIG{'__DIE__'};

          my $hdr = $obj->header($typ, \%args);

          my $r = 0;
          if(sysopen( FH, $file, O_RDONLY|O_BINARY )) {  
            $handle->print($hdr);

            my $bytes;
            my $data;
            do {
              $bytes = sysread( FH, $data, 4096 );
              if($bytes) {
                $r = $handle->send($data);
              }
            } while $r && $bytes > 0;
            close(FH);
          } else {
            error sprintf("I can't open file '%s' : %s", $file,$!);
          }
          $handle->close();
        };
        error($@) if $@;
        exit 0;
      }

      undef $obj->{handle};
      undef $obj->{output};
    } else {

        my $data = load_file($file)
            or return $obj->status404($file,$!);
        # send data
        $obj->out($data, $typ, %args );
    }
}

# ------------------
sub image {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $file = shift || return error ('No File!');
    my $typ = shift;
    return $obj->datei($file,$typ);
}

# ------------------
sub pod {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $modname = uc(shift) || return error ('No Modname!' );
    $modname = ucfirst($modname) if($modname eq 'GENERAL');

    my $podfile = sprintf('%s/%s.pod', $obj->{paths}->{PODPATH}, $modname);
    return $obj->err(gettext('Module %s not found!'), $modname)
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
    $obj->link({
        text => gettext("Back to configuration screen"),
        url => $obj->{browser}->{Referer},
    });

    $obj->message($html);
}

# ------------------
sub txtfile {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $filename = shift || return error ('No TxtFile to display!' );
    my $param = shift || {};

    my $txtfile = sprintf('%s/%s.txt', $obj->{paths}->{DOCPATH}, $filename);
    my $gzfile  = sprintf('%s/%s.txt.gz', $obj->{paths}->{DOCPATH}, $filename);

    $txtfile = main::getModule('HTTPD')->unzip($gzfile)
        if(! -r $txtfile and -r $gzfile);

    my $topic = gettext("File");

    if($param->{'format'} eq 'txt') {
        my $txt = load_file($txtfile);
        return $obj->message($txt, {tags => {first => "$topic: $filename.txt"}});
    }

    my $u = main::getModule('USER');
    my $htmlfile = sprintf('%s/temp_txt.html', $u->userTmp);

    $obj->{txt2html}->txt2html(
                     infile=>[$txtfile],
                     outfile=>$htmlfile,
                     title=> $filename,
                     mail=>1,
    );
    my $html = load_file($htmlfile);
    $html = $1 if($html =~ /\<body.*?\>(.+?)\<\/body\>/si);
    $obj->message($html, {tags => {first => "<h1>$topic: $filename.txt</h1>"}});
}

# ------------------
sub typ {
# ------------------
    my $obj = shift || return error ('No Object!' );
    return $obj->{TYP};
}

# ------------------
sub setCall {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return error ('No Name!' );

    $obj->{call} = $name;
    return $obj->{call};
}

# ------------------
sub browser {
# ------------------
    my $obj = shift || return error ('No Object!' );
    return $obj->{browser};
}

# Special Version from Message (with error handling)
# ------------------
sub msg {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $data = shift || 0;
    my $err = shift  || 0;

    unless($err) {
        $obj->message($data);
    } else {
        $obj->err($data || $err);
        return undef;
    }
}

# ------------------
sub parseData {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $dta = shift  || return '';

    if(ref $dta eq 'HASH') {
        foreach my $name (keys %$dta) {
            if(ref $dta->{$name}) {
                $obj->parseData($dta->{$name});
            } else {
                $dta->{$name} = reentities($dta->{$name}) if($obj->{hasentities});
                $dta->{$name} = entities($dta->{$name});
            }
        }
    } elsif (ref $dta eq 'ARRAY') {
        foreach (@$dta) {
            if(ref $_) {
                $obj->parseData($_);
            } else {
                $_ = reentities($_) if($obj->{hasentities});
                $_ = entities($_);
            }
        }
    }
    $obj->{hasentities} = 1;
    return $dta;
}


1;
