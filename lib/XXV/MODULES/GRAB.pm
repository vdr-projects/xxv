package XXV::MODULES::GRAB;
use strict;

use Tools;
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
                check   => sub{
                    my $value = shift || 0;
                    if($value =~ /^\d+$/sig and $value >= 8 and $value < 4096) {
                        return int($value);
                    } else {
                        return undef, gettext('Value incorrect!');
                    }
                },
            },
            ysize => {
                description => gettext('Image height'),
                default     => 240,
                type        => 'integer',
                required    => gettext('This is required!'),
                check   => sub{
                    my $value = shift || 0;
                    if($value =~ /^\d+$/sig and $value >= 8 and $value < 4096) {
                        return int($value);
                    } else {
                        return undef, gettext('Value incorrect!');
                    }
                }
            },
            overlay => {
                description => gettext('Text to display in the grabbed picture.'),
                default     => "<< event.POS >>.<< event.Channel >>\|<< event.Title >> << event.Subtitle >>",
                type        => 'string',
                check   => sub{
                    my $value = shift;
                    $value = join('|',(split(/[\r\n]/, $value)));
                    return $value;
                },
            },
            vpos => {
                description => gettext('Vertical position of displayed text, in pixels.'),
                default     => 10,
                type        => 'integer',
                check   => sub{
                  my $value = shift || 0;
                  if($value =~ /^\d+$/sig and $value >= 8 and $value < 4096) {
                    return int($value);
                  } else {
                    return undef, gettext('Value incorrect!');
                  }
               }
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
                check   => sub{
                  my $value = shift || 0;
                  if($value =~ /^\d+$/sig and $value >= 1 and $value < 100) {
                      return int($value);
                  } else {
                      return undef, gettext('Value incorrect!');
                  }
               }
            },
            imgquality => {
                description => gettext('Quality from image in percent.'),
                default     => 80,
                type        => 'integer',
                check   => sub{
                  my $value = shift || 0;
                  if($value =~ /^\d+$/sig and $value >= 1 and $value < 100) {
                    return int($value);
                  } else {
                    return undef, gettext('Value incorrect!');
                  }
               }
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
                binary      => 'nocache'
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
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # create Template object
    $self->{tt} = Template->new(
      START_TAG    => '\<\<',		        # Tagstyle
      END_TAG      => '\>\>',		        # Tagstyle
      INTERPOLATE  => 1,                # expand "$var" in plain text
      PRE_CHOMP    => 0,                # cleanup whitespace
      EVAL_PERL    => 0,                # evaluate Perl code blocks
    );

    $self->_init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift  || return error('No object defined!');

    main::after(sub{
          $obj->{svdrp} = main::getModule('SVDRP');
          unless($obj->{svdrp}) {
            panic ("Couldn't get modul SVDRP");
            return 0;
          }
          return 1;
        }, "GRAB: init modul ...");
    return 1;
}

# ------------------
sub grab {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    # command for get inline data (JPEG BASE64 coded)
    my $cmd = sprintf('grab - %d %d %d',
            $obj->{imgquality},
            $obj->{xsize},
            $obj->{ysize},
    );

    my $data = $obj->{svdrp}->command($cmd);
    
    my $binary;
    foreach my $l (@{$data}) { 
      if($l =~ /^216-/sg) { 
        $l =~ s/^216-//g;
        $binary .= MIME::Base64::decode_base64($l); 
      } 
    }
    # create noised image as failback. 
    $binary = $obj->_noise() 
      unless($binary);

    if($data && $binary) {
      # Make overlay on image
      $binary = $obj->makeImgText($binary, $obj->{overlay})
          if($obj->{overlay});
    }
    return $binary;
}

# ------------------
sub display {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');

    my $binary = $obj->grab();
    if($binary) { #  Datei existiert und hat eine Grösse von mehr als 0 Bytes
      $console->{nocache} = 1;
      $console->{nopack} = 1;
      my %args = ();
      $args{'attachment'} = 'grab.jpg';
      $args{'Content-Length'} = length($binary);
      return $console->out($binary, 'image/jpeg', %args );
    }
}

# ------------------
sub makeImgText {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $binary = shift || return error ('No data to create overlay defined!');
    my $text = shift || return error ('No text to display defined!');

    my $image = GD::Image->newFromJpegData($binary);
    unless($image && $image->width > 8 && $image->height > 8) {
      return error("Data has'nt jpeg data or jpeg data contains errors!");
    }
    my $color   = $image->colorClosest(255,255,255);
    my $shadow  = $image->colorClosest(0,0,0);

    my $event = main::getModule('EPG')->NowOnChannel(undef,undef);

    # Hier sollten noch mehr Informationen dazu kommen
    my $vars = {
        event => $event,
    };

    my $output = '';
    $obj->{tt}->process(\$text, $vars, \$output)
          or return error($obj->{tt}->error());


    my $font = sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font});
    if($obj->{paths}->{FONTPATH} and $obj->{font} and -r $font) {
      my $height = ($obj->{imgfontsize} + 2);
      $height *= -1 if($obj->{vpos} > ($obj->{ysize} / 2));

      my $offset = 0;
      foreach my $zeile (split(/\|/, $output)) {
        $image->stringFT($shadow,$font,$obj->{imgfontsize},0,11,($obj->{vpos}-1)+$offset,$zeile);
        $image->stringFT($color,$font,$obj->{imgfontsize},0,10,($obj->{vpos})+$offset,$zeile);
        $offset += $height;
      }
    } else {
      my $height = 12;
      $height *= -1 if($obj->{vpos} > ($obj->{ysize} / 2));

      my $offset = 0;
      foreach my $zeile (split(/\|/, $output)) {
        $image->string(&gdGiantFont,11, ($obj->{vpos}-1) + $offset,$zeile,$shadow); # Schatten
        $image->string(&gdGiantFont,10, ($obj->{vpos}) + $offset,$zeile,$color);    # Text
        $offset += $height;
      }
    }

    my $img_data = $image->jpeg($obj->{imgquality});
    return $img_data;
}

sub _noise {
    my $obj = shift || return error('No object defined!');
    my $image = GD::Image->new($obj->{xsize}, $obj->{ysize},1);
  
    my $colors;
    push( @{$colors}, $image->colorClosest(255,255,255));
    push( @{$colors}, $image->colorClosest(128,128,128));
    push( @{$colors}, $image->colorClosest(0,0,0));

    $obj->_noise_rect($image,0,0,$obj->{xsize},$obj->{ysize},$colors);
    my $img_data = $image->jpeg($obj->{imgquality});
    return $img_data;
}

sub _noise_rect {
    my $obj = shift || return error('No object defined!');
    my $image = shift;
    my $x1 = shift; my $y1 = shift;
    my $x2 = shift; my $y2 = shift;
    my $colors_ref = shift;
    my $colorcount = scalar @{$colors_ref};

    return if $x2 <= $x1;  # refuse to create a zero- or negative-size box
    return if $y2 <= $y1;

    for (my $x = $x1; $x < $x2; ++$x) {
      for (my $y = $y1; $y < $y2; ++$y) {
        $image->setPixel($x, $y,$colors_ref->[CORE::int(rand($colorcount))]);
      }
    }

    return;
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
    error "Couldn't find useful font at : ", $obj->{paths}->{FONTPATH}
        if(scalar $found == 0);
    return $found;
}

1;
