package XXV::OUTPUT::Wml;

use strict;

use vars qw($AUTOLOAD);
use Tools;
use File::Path;
use Pod::Html;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'Wml',
        Prereq => {
            'Template'  => 'Front-end module to the Template Toolkit',
        },
        Description => gettext('This receives and sends WAP messages.'),
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
        return panic("\nCouldn't load perl module: $_\nPlease install this module on your system:\nperl -MCPAN -e 'install $_'") if($@);
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
        || return error('No cgi object given!');

    $self->{mime} = $attr{'-mime'}
        || return error('No mime hash given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No browser given!');

    $self->{charset} = $attr{'-charset'}
        || 'ISO-8859-1';

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
    my $self = shift || return error('No object defined!');
    my $name = shift || return error('No name defined!');
    my $data = shift || return error('No data defined!');
    my $params = shift || {};

    my $t = $self->{tt};
    my $u = main::getModule('USER');

    # you can use two templates, first is a user defined template
    # and second the standard template
    # i.e. call the htmlhelp command the htmlhelp.tmpl
    # SpecialTemplate:  ./wmlRoot/usage.tmpl
    # StandardTemplate: ./wmlRoot/widgets/menu.tmpl
    my $widget_first  = sprintf('%s.tmpl', (exists $self->{call}) ? $self->{call} : 'nothing');
    my $widget_second = sprintf('widgets/%s.tmpl', $name);
    my $widget = (-e sprintf('%s/%s', $self->{wmldir}, $widget_first) ? $widget_first : $widget_second);
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
        debug   => 1,
        user    => $user,
        charset => $self->{charset},
        allow   => sub{
            my($cmdobj, $cmdname, $se, $err) = $u->checkCommand($self, $_[0],"1");
            return 1 if($cmdobj);
        },
	    basedir => $self->{wmldir},
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
    my $self = shift || return error('No object defined!');
    my $text = shift || 'no Text for Output';
    my $type = shift || 'text/vnd.wap.wml';
    my %args = @_;

    my $q = $self->{cgi};
    unless(defined $self->{header}) {
        # HTTP Header
        $self->{handle}->print(
            $self->header($type, \%args)
        );
    }

    $self->{handle}->print( $text,"\r\n" );
}

# ------------------
sub header {
# ------------------
    my $self = shift || return error('No object defined!');
    my $typ = shift || return error ('No Type!' );
    my $arg = shift || {};

    $self->{header} = 1;
    return $self->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => ($typ =~ 'text/vnd.wap.wml' || (defined $self->{nocache} && $self->{nocache})) ? "now" : "+12h",
        -charset => $self->{charset},
        %{$arg},
    );
}

# ------------------
sub statusmsg {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $msg = shift || return error ('No Msg!');
    my $status = shift || return error ('No Status!');

    unless(defined $self->{header}) {
        $self->{nopack} = 1;
        $self->{header} = 1;
        my $data = $self->{cgi}->header(
            -type   =>  'text/vnd.wap.wml',
            -status  => $status,
            -expires => "now",
        );
        $self->out($data);
    }

    my @title = split ('\n', $status);
    $self->start(undef,{ title => $title[0] });
    $self->err($msg);
    $self->footer();
}

# ------------------
# Send HTTP Status 401 (Authorization Required)
sub login {
# ------------------
    my $self = shift || return error('No object defined!');
    my $msg = shift || '';

    $self->statusmsg($msg,"401 Authorization Required\nWWW-Authenticate: Basic realm=\"xxvd\"");
}

# ------------------
# Send HTTP Status 403 (Access Forbidden)
sub status403 {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $msg = shift  || '';

    $self->statusmsg($msg,"403 Forbidden");
}


# ------------------
# Send HTTP Status 404 (File not found)
sub status404 {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $why = shift || "";

    lg sprintf("Couldn't open file '%s' : %s!",$file,$why);

    $file =~ s/$self->{wmldir}\///g; # Don't post wml root, avoid spy out

    $self->statusmsg(sprintf(gettext("Couldn't open file '%s' : %s!"),$file,$why),"404 File not found");
}

# ------------------
sub question {
# ------------------
    my $self         = shift || return error('No object defined!');
    my $titel       = shift || 'undef';
    my $questions   = shift || return error('No data defined!');
    my $erg         = shift || 0;

    my $q = $self->{cgi};
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
                ($erg->{$name}, $error) = (undef, sprintf(gettext("Directory '%s' does not exist!"), $erg->{$name}));
            }

            # Check on file
            if($data->{typ} eq 'file' and $data->{required} and not -e $erg->{$name}) {
                ($erg->{$name}, $error) = (undef, sprintf(gettext("File '%s' does not exist!"), $erg->{$name}));
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
        while (my ($name, $data) = splice(@$quest, 0, 2)) {
            my $type = delete $data->{typ};
            $data->{msg} =~ s/\n/<br \/>/sig if($data->{msg});
            $data->{NAME} = '__'.$name;
            $type ||= 'string';
            $self->$type($data);
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
sub image {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $typ = shift  || $self->{mime}->{lc((split('\.', $file))[-1])}
        or return error("No Type in Mimehash or File: $file");

    my $data = load_file($file)
        or return $self->status404($file,$!);

    $self->out($data, $typ);
}

# ------------------
sub datei {
# ------------------
    my $self = shift || return error('No object defined!');
    my $file = shift || return error('No file defined!');

    my $data = load_file($file)
        or return $self->status404($file,$!);

    $self->out($data, 'text/vnd.wap.wml');
}

# ------------------
sub pod {
# ------------------
    my $self = shift || return error('No object defined!');
    my $modname = shift || return error('No modul name defined!');
    $modname = ucfirst($modname) if($modname eq 'GENERAL');

    my $podfile = sprintf('%s/%s.pod', $self->{paths}->{PODPATH}, $modname);
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
    $self->link({
        text => gettext("Back to configuration page."),
        url => $self->{browser}->{Referer},
    });
    $self->message($html);
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
    my $name = shift || return error('No name defined!');

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
    my $self = shift || return error('No object defined!');
    my $data = shift || {};
    my $err = shift;

    unless($err) {
        $self->message($data);
    } else {
        $self->err($data);
    }
}



1;
