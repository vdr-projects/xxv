package XXV::OUTPUT::Wml;

use strict;

use vars qw($AUTOLOAD);
use Locale::gettext;
use Tools;
use File::Path;
use Pod::Html;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'Wml',
        Prereq => {
            'Template'  => 'Front-end module to the Template Toolkit ',
        },
        Description => gettext('This receive and send Wap messages.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
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

    $self->{wmldir} = $attr{'-wmldir'}
        || return error('No wmldir given!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No TemplateDir given!');

    $self->{mime} = $attr{'-mime'}
        || return error('No Mimehash given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No Mimehash given!');

#    $self->{start} = $attr{'-start'}
#        || return error('No StartPage given!');

    $self->{TYP} = 'WML';

    eval "use Template::Stash::XS";
    $Template::Config::STASH = 'Template::Stash::XS' unless($@);

    # create Template object
    $self->{tt} = Template->new(
      START_TAG    => '\<\?\%',		    # Tagstyle
      END_TAG      => '\%\?\>',		    # Tagstyle
      INCLUDE_PATH => $self->{wmldir},  # or list ref
      INTERPOLATE  => 1,                # expand "$var" in plain text
      PRE_CHOMP    => 1,                # cleanup whitespace
      EVAL_PERL    => 1,                # evaluate Perl code blocks
    );

	return $self;
}

# ------------------
sub parseTemplate {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return error ('No Name!' );
    my $data = shift || return error ('No Data!' );
    my $params = shift || {};

    my $t = $obj->{tt};
    my $u = main::getModule('USER');

    # you can use two templates, first is a user defined template
    # and second the standard template
    # i.e. call the htmlhelp command the htmlhelp.tmpl
    # SpecialTemplate:  ./wmlRoot/usage.tmpl
    # StandardTemplate: ./wmlRoot/widgets/menu.tmpl
    my $widget_first  = sprintf('%s.tmpl', (exists $obj->{call}) ? $obj->{call} : 'nothing');
    my $widget_second = sprintf('widgets/%s.tmpl', $name);
    my $widget = (-e sprintf('%s/%s', $obj->{wmldir}, $widget_first) ? $widget_first : $widget_second);
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
        debug   => 1,
        user    => $user,
        allow   => sub{
            my($cmdobj, $cmdname, $se, $err) = $u->checkCommand($obj, $_[0],"1");
            return 1 if($cmdobj);
        },
	    basedir => $obj->{wmldir},
        entities => sub{ return entities($_[0]) },
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
    my $type = shift || 'text/vnd.wap.wml';
    my %args = @_;

    my $q = $obj->{cgi};
    unless(defined $obj->{header}) {
        # HTTP Header
        $obj->{handle}->print(
            $obj->header($type, \%args)
        );
    }

    $obj->{handle}->print( $text,"\r\n" );
}

# ------------------
sub header {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $typ = shift || return error ('No Type!' );
    my $arg = shift || {};

    $obj->{header} = 1;
    return $obj->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => ($typ =~ 'text/vnd.wap.wml' || (defined $obj->{nocache} && $obj->{nocache})) ? "now" : "+12h",
        %{$arg},
    );
}

# ------------------
sub statusmsg {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $msg = shift || return error ('No Msg!');
    my $status = shift || return error ('No Status!');

    unless(defined $obj->{header}) {
        $obj->{nopack} = 1;
        $obj->{header} = 1;
        my $data = $obj->{cgi}->header(
            -type   =>  'text/vnd.wap.wml',
            -status  => $status,
            -expires => "now",
        );
        $obj->out($data);
    }

    my @title = split ('\n', $status);
    $obj->start(undef,{ title => $title[0] });
    $obj->err($msg);
    $obj->footer();
}

# ------------------
# Send HTTP Status 401 (Authorization Required)
sub login {
# ------------------
    my $obj = shift || return error ('No Object!');
    my $msg = shift || '';

    $obj->statusmsg($msg,"401 Authorization Required\nWWW-Authenticate: Basic realm=\"xxvd\"");
}

# ------------------
# Send HTTP Status 403 (Access Forbidden)
sub status403 {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $msg = shift  || '';

    $obj->statusmsg($msg,"403 Forbidden");
}


# ------------------
# Send HTTP Status 404 (File not found)
sub status404 {
# ------------------
    my $obj = shift  || return error ('No Object!');
    my $file = shift || return error ('No File!');
    my $why = shift || "";

    warn("I can't read file $file");

    $file =~ s/$obj->{wmldir}\///g; # Don't post wml root, avoid spy out

    $obj->statusmsg(sprintf(gettext("Can't open file '%s' : %s"),$file,$why),"404 File not found");
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
            # Required value ...
            $error = $data->{req}
                if($data->{req} and not $erg->{$name});

            # Check Callback
            if(exists $data->{check} and ref $data->{check} eq 'CODE' and not $error) {
                ($erg->{$name}, $error) = $data->{check}($erg->{$name}, $data);
            }

            # Check on directory
            if($data->{typ} eq 'dir' and $data->{required} and not -d $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("Directory '%s' is doesn't exist!"), $erg->{$name}));
            }

            # Check on file
            if($data->{typ} eq 'file' and $data->{required} and not -e $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("File '%s' is doesn't exist!"), $erg->{$name}));
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
        while (my ($name, $data) = splice(@$quest, 0, 2)) {
            my $type = delete $data->{typ};
            $data->{msg} =~ s/\n/<br \/>/sig if($data->{msg});
            $data->{NAME} = '__'.$name;
            $type ||= 'string';
            $obj->$type($data);
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
sub image {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $file = shift || return error ('No File!' );
    my $typ = shift  || $obj->{mime}->{lc((split('\.', $file))[-1])}
        or return error("No Type in Mimehash or File: $file");

    my $data = load_file($file)
        or return $obj->status404($file,$!);

    $obj->out($data, $typ);
}

# ------------------
sub datei {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $file = shift || return error ('No File!' );

    my $data = load_file($file)
        or return $obj->status404($file,$!);

    $obj->out($data, 'text/vnd.wap.wml');
}

# ------------------
sub pod {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $modname = shift || return error ('No Modname!' );
    $modname = ucfirst($modname) if($modname eq 'GENERAL');

    my $podfile = sprintf('%s/%s.pod', $obj->{paths}->{PODPATH}, $modname);
    my $tmpdir = main::getModule('USER')->userTmp;
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
    my $obj = shift || return error ('No Object!' );
    my $data = shift || {};
    my $err = shift;

    unless($err) {
        $obj->message($data);
    } else {
        $obj->err($data);
    }
}



1;
