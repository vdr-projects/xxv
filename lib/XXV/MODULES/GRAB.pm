package XXV::MODULES::GRAB;
use strict;

use Tools;
use Locale::gettext;
use File::Basename;
use File::Find;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'GRAB',
        Prereq => {
            'GD'        => 'image manipulation routines',
            'Template'  => 'Front-end module to the Template Toolkit ',
        },
        Description => gettext('This module grab a picture from livestream.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            xsize => {
                description => gettext('Image width'),
                default     => 320,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            ysize => {
                description => gettext('Image height'),
                default     => 240,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            file => {
                description => gettext('Location where the grabbed image file will be stored'),
                default     => '/tmp/live.jpg',
                type        => 'file',
            },
            imgtext => {
                description => gettext('Text to display in the grabbed picture.'),
                default     => "[?- i = channel.split(' ') -?][[? i.shift ?]] [? i.join(' ') ?]",
                type        => 'string',
            },
            vpos => {
                description => gettext('Vertical position of displayed text, in pixels.'),
                default     => 10,
                type        => 'integer',
            },
            font => {
                description => gettext('TrueType font to draw overlay text'),
                default     => 'VeraIt.ttf',
                type        => 'list',
                choices     => $obj->findttf,
            },
            imgfontsize => {
                description => gettext('Font size to draw image text (only for ttf font!).'),
                default     => 10,
                type        => 'integer',
            },
            imgquality => {
                description => gettext('Quality from image in percent.'),
                default     => 80,
                type        => 'integer',
            },
        },
        Commands => {
            grab => {
                description => gettext('Grab a picture'),
                short       => 'gr',
                callback    => sub{ $obj->grab(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            gdisplay => {
                description => gettext('Display the picture'),
                short       => 'gd',
                callback    => sub{ $obj->display(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
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
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_};
        $self->{$_} = $self->{MOD}->{Preferences}->{$_}->{default} unless($self->{$_});
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # create Template object
    $self->{tt} = Template->new(
      START_TAG    => '\[\?',		    # Tagstyle
      END_TAG      => '\?\]',		    # Tagstyle
      INTERPOLATE  => 1,                # expand "$var" in plain text
      PRE_CHOMP    => 1,                # cleanup whitespace
      EVAL_PERL    => 1,                # evaluate Perl code blocks
    );

    $self->_init or return error('Problem to initialize module');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift  || return error('No object defined!');

    main::after(sub{
          $obj->{svdrp} = main::getModule('SVDRP');
          unless($obj->{svdrp}) {
            panic ("Can't get modul SVDRP");
            return 0;
          }
          return 1;
        }, "GRAB: Init module ...");
    return 1;
}

# ------------------
sub grab {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $file    = $obj->{file};
    my $erg;

    if(main::getVdrVersion() >= 10338) {

        # command for get inline data (JPEG BASE64 coded)
        my $cmd = sprintf('grab - %d %d %d',
                $obj->{imgquality},
                $obj->{xsize},
                $obj->{ysize},
        );

        my $data = $obj->{svdrp}->command($cmd);
        my $uu = [ grep(/^216-/, @$data) ];
        foreach (@{$uu}) { s/^216-//g; }

        if(scalar @{$uu} <= 0) {
            # None data with 216-, maybe svdrp message contain reason
            $erg = $data;
        } elsif(!open(F, ">$file")) {
            # Open failed
            $erg = sprintf("Can't write to file %s : %s",$file,$!);
        } else {
            # uudecode data to file
            binmode(F);
            foreach (@{$uu}) { print F MIME::Base64::decode_base64($_); }
            close F;
        }
    } else {

        if(-e $file) {
          unlink($file) || error("Can't remove '%s' : %s",$file,$!);
        }
        # the command
        my $cmd = sprintf('grab %s jpeg %d %d %d',
                $obj->{file},
                $obj->{imgquality},
                $obj->{xsize},
                $obj->{ysize},
        );

        $erg = $obj->{svdrp}->command($cmd);
    }
    # Make imgtext
    $file = $obj->makeImgText($file, $obj->{imgtext})
        if($obj->{imgtext} && -s $file);

    $console->msg($erg, $obj->{svdrp}->err)
        if(ref $console);
    return $file;
}

# ------------------
sub display {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $file = $obj->grab();
    if(-s $file) { #  Datei existiert und hat eine Grösse von mehr als 0 Bytes
      $console->{nocache} = 1;
      return $console->image($file);
    } else {
      error("Can't locate file : $file, maybe grabbing was failed");
      return 0;
    }
}

# ------------------
sub makeImgText {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $file = shift || $obj->{file} || return error ('No File to display');
    my $text = shift || $obj->{imgtext} || return error ('No Text to display');

    my $im;
    if(int(${GD::VERSION}) >= 2.0) {
        $im = GD::Image->newFromJpeg($file, 1) || return error("Can't read $file $!");
    } else {
        $im = GD::Image->newFromJpeg($file) || return error("Can't read $file $!");
    }
    my $color   = $im->colorClosest(255,255,255);
    my $shadow  = $im->colorClosest(0,0,0);


    # XXX: Hier sollten noch mehr Informationen dazu kommen
    my $channeltext = main::getModule('REMOTE')->switch();
    my $channelpos = (split(' ', $channeltext))[0];
    my $vars = {
        channel => $channeltext,
        event => main::getModule('EPG')->NowOnChannel($watcher, $console, $channelpos),
    };

    my $output = '';
    $obj->{tt}->process(\$text, $vars, \$output)
          or return error($obj->{tt}->error());

    my $font = sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font});
    if($obj->{paths}->{FONTPATH} and $obj->{font} and -r $font) {
        $im->stringFT($shadow,$font,$obj->{imgfontsize},0,11,($obj->{vpos}-1),$output);
        $im->stringFT($color,$font,$obj->{imgfontsize},0,10,($obj->{vpos}),$output);
    } else {
        # Schatten
        $im->string(&gdGiantFont,11, ($obj->{vpos}-1),$output,$shadow);
        # Text
        $im->string(&gdGiantFont,10, ($obj->{vpos}),$output,$color);
    }

    my $img_data = $im->jpeg($obj->{imgquality});
    my @f = split('\.', $file);
    my $newfile = ($file =~ 'text' ? $file : sprintf('%s_text.%s', @f));
    save_file($newfile, $img_data);
    return $newfile;
}

# ------------------
sub findttf
# ------------------
{
    my $obj = shift || return error('No object defined!');
    my $found;
    find({ wanted => sub{
                if($File::Find::name =~ /\.ttf$/sig) {
                    my $l = basename($File::Find::name);
                    push(@{$found},[$l,$l]);
                }
           },
           follow => 1,
           follow_skip => 2,
        },
        $obj->{paths}->{FONTPATH}
    );
    error "Can't find useful font at : ", $obj->{paths}->{FONTPATH}
        if(scalar $found == 0);
    return $found;
}

1;
