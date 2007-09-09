package XXV::MODULES::VTX;

use strict;

use File::Find;
use FileHandle;
use Locale::gettext;

################################################################################
# This module method must exist for XXV
sub module {
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'VTX',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module display cached teletext pages from osdteletext-plugin.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'Andreas Brachold',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
            },
            dir => {
                description => gettext('Directory where the teletext files are be located'),
                default     => '/vtx',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
            cache => {
                description => gettext("Used cache system.\nChoose 'legacy' for the traditional one-file-per-page system.\nDefault is 'packed' for the one-file-for-a-few-pages system.\nVDR-osdteletext-Plugin\n'legacy' <= osdteletext-0.3.2 or 'packed' >= osdteletext-0.4.0"),
                default     => 'packed',
                type        => 'radio',
                required    => gettext('This is required!'),
                choices     => ['legacy','packed']
            },
        },
        Commands => {
            vtxpage => {
                description => gettext("Display the teletext page 'pagenumber'"),
                short       => 'vt',
                callback    => sub{ $self->page(@_) },
            },
            vtxchannel => {
                description => gettext("Channel for teletext actions 'cid'"),
                short       => 'vc',
                callback    => sub{ $self->channel(@_) },
            },
            vtxsearch => {
                description => gettext("Search for text inside teletext pages 'text'"),
                short       => 'vs',
                callback    => sub{ $self->search(@_) },
            },
        },
    };
    return $args;
}

################################################################################
# Ctor
sub new {
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

    return $self;
}


################################################################################
# Find first usable channel
sub findfirst {

	my $self = shift || return error ('No Object!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $basedir = $self->{dir}
        || return $self->pagedump($console,gettext("directory is for modul vtx not registered!"),"");

	my $mod = main::getModule ('CHANNELS');
	my $channels =[];

	my $cache = $self->{cache} ||'packed';
	if ($cache ne 'packed') {
		foreach my $ch (@{$mod->ChannelArray ('Name')}) {
			if (-d $basedir.'/'.$ch->[1]) {
				return $self->channel ($watcher, $console,$ch->[1]);
			}
		}
   } else {
        foreach my $ch (@{$mod->ChannelArray ('Id')}) {
            if (-d $basedir.'/'.$ch->[0]) {
                return $self->channel ($watcher,$console,$ch->[1]);
            }
        }
    }
}

################################################################################
# Callback "Channel choice"
sub channel
{
    my $self = shift || return error ('No Object!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $channel = shift || return $self->findfirst ($watcher, $console);

    my $basedir = $self->{dir} || return error ('No Base Directory defined !');
    my $cache = $self->{cache} || 'packed';

    my $mod = main::getModule ('CHANNELS');

    my $chandir = "";
    my $channelname = "";

    # Get ChannelID and channel's Name
    foreach my $ch (@{$mod->ChannelArray ('Name, Id')}) {
        if ($ch->[2] == $channel) {
            $channelname = $ch->[0];
            if ($cache eq 'packed') {
                $chandir = $ch->[1];
            } else {
                $chandir = $channel;
            }
            last;
        }
    }


    if ($channelname ne ""
        and $chandir ne ""
        and -d "$basedir/$chandir")  {

        $self->{CHANNEL}= $channel;
        $self->{CHANNELDIR}= $chandir;
        {
            $self->{INDEX} = [];
            my @index;
            if ($cache eq 'packed') {
                find(
                    sub{
                       if($File::Find::name =~ /\d{3}s.vtx$/sig) {
                            push(@index,GetPackedToc($File::Find::name));
                        }
                    },"$basedir/$chandir");
            } else {
                find(
                    sub{
                        if($File::Find::name =~ /\d{3}_\d{2}.vtx$/sig) {
                            my ($page, $subpage)
                                = $File::Find::name =~ /^.*(\d{3})_(\d{2}).*/si;
                            if($page and $subpage) {
                                my $found = 0;
                                foreach my $p (@index) {
                                    if($p->[0] == $page) {
                                        $found = 1;
                                        push(@{$p->[1]},$subpage)
                                            if($subpage != 0);
                                        last;
                                    }
                                }
                                if ($found == 0) {
                                    push(@index,[$page, [$subpage] ]);
                                }
                            }
                        }
                    },"$basedir/$chandir");
                }
                if (scalar @index == 0) {
                    $self->pagedump($console,sprintf(gettext("No data found for \'%s\'!"),$channelname),"");
                    return;
            }
            # Seitenindex sortieren
            @{$self->{INDEX}} = sort { $a->[0] <=> $b->[0] } @index;
            # Subseitenindex sortieren
            foreach my $p (@{$self->{INDEX}}) {
                if (scalar @{$p->[1]} > 1) {
                    my @tmp = sort { $a <=> $b } @{$p->[1]};
                    @{$p->[1]} = @tmp;
                }
            }
        }

# Dump PageIndex
#           foreach my $p (@{$self->{INDEX}}) {
#               my $dump = "Pages $p->[0]";
#               foreach my $s (@{$p->[1]}) {
#                  $dump .= ", $s";
#               }
#               warn($dump);
#      }

        $console->message(sprintf(gettext("channel \'%s\' for modul vtx registered."),$channelname))
            if ($console->{TYP} ne 'HTML') ;
    } else {
        $self->pagedump($console,sprintf(gettext("No data found for \'%s\'!"),$channelname),"");
        return;
    }
    my $fpage = @{$self->{INDEX}}[0];# First Page on Index
    return $self->page ($watcher, $console,sprintf ("%03d_%02d", $fpage->[0],$fpage->[1]->[0]));
}

################################################################################
# Callback "Teletextpage choice"
sub page {
    my $self = shift || return error ('No Object!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $page = shift || "";
    my $channel = $self->{CHANNEL} || return $self->findfirst ($watcher, $console);
    my $basedir = $self->{dir} || return error ('No Base Directory defined !');
    my $chandir  = $self->{CHANNELDIR} || return error ('No CHANNEL');
    my $cache = $self->{cache} || 'packed';

    my @pp = split ('_', $page);
    if (scalar @pp == 0) {
       # First Page on Index
       my $fpage = @{$self->{INDEX}}[0];
       $pp[0] = sprintf("%3d",$fpage->[0]);
       $pp[1] = sprintf("%2d",$fpage->[1]->[0]);
    }
    elsif (scalar @pp == 1) {
        # First Subpage on Index
        $pp[1] = "00";
        foreach my $fpage (@{$self->{INDEX}}) {
            if($fpage->[0] == $pp[0]) {
                $pp[1] = sprintf("%2d",$fpage->[1]->[0]);
                last;
            }
        }
    }
    my $bHTML = ($console->{TYP} ne 'HTML')?0:1;
    my $result = $self->realpage($console, $pp[0], $pp[1],$bHTML);

    return 0 if($result eq "");
    return $self->pagedump($console,$result,$chandir);
}

################################################################################
# Generate Message
sub pagedump {
    my $self = shift || return error ('No Object!');
    my $console = shift || return error ('No Console');
    my $result = shift;
    my $chandir = shift;

    if ($console->{TYP} ne 'HTML') {
        return $console->message ($result);
    } else  {

        my $charray =[];
        my $chsel = $self->{CHANNELDIR};
        my $cache = $self->{cache};
        my $basedir = $self->{dir};
        my $mod = main::getModule ('CHANNELS');

        my @chan = (@{$mod->ChannelArray ('Name, Id')});
        if ($cache ne 'packed') {
            foreach my $ch (@chan) {
                push (@$charray, [$ch->[0], $ch->[2]])
                    if (-d $basedir.'/'.$ch->[2]) ; # Lookup /vtx/25/
            }
        } else {
            foreach my $ch (@chan){
                if (-d $basedir.'/'.$ch->[1])  { # Lookup /vtx/S19.2E-1-1101-28108/
                    push (@$charray, [$ch->[0], $ch->[2]]);
                    $chsel = $ch->[2]
                        if ($ch->[1] eq $chandir) ;
                }
            }
        }

        my @lines = $self->InsertPageLink($result);
        $self->NavigatePages();
        my $tmpldata =
        {
          channel => $chsel,
          channels => $charray,
          page => $self->{mainpage},
          subpage => $self->{subpage},
          toppage => $self->{toppage},
          page_prev => $self->{page_prev},
          page_next => $self->{page_next},
          subpage_prev => $self->{subpage_prev},
          subpage_next => $self->{subpage_next}
        };

        $console->{dontparsedData} = 1;
        return $console->vtx(\@lines, $tmpldata);
    }
    return 1;
}

################################################################################
# Insert for HTML Pages, Link for other Pages
sub InsertPageLink {

  my $self = shift;
  my $result = shift;
  my @lines;

  # Replace XXX => <a href="?cmd=vt&amp;data=XXX">XXX</a>
  my $ua = "<a class='vtx' href='?cmd=vt&amp;data=";
  my $ub = "'>";
  my $uc = "</a>";

  foreach my $line (split('\n',$result)) {
    my ($page1,$page2) = $line =~ /\D+([1-8]\d{2})\D+([1-8]\d{2})\D+/s;
    if($page1 and $page2) {
      foreach my $p (@{$self->{INDEX}}) {
        if($p->[0] == $page1) {
          $line =~ s/$page1/$ua.$page1.$ub.$page1.$uc/eg;
        } elsif($p->[0] == $page2) {
          $line =~ s/$page2/$ua.$page2.$ub.$page2.$uc/eg;
          last;
        }
      }
    } else {
      my ($page1) = $line =~ /\D+([1-8]\d{2})\D+/s;
      if($page1) {
        foreach my $p (@{$self->{INDEX}}) {
          if($p->[0] == $page1) {
            $line =~ s/$page1/$ua.$page1.$ub.$page1.$uc/eg;
            last;
          }
        }
      }
    }
    
    # Make anchor for external URLs
    $line =~ s/((www)\.[a-z0-9\.\/\-]+)/<a target=\"blank\" class=\"vtx\" href=\"http:\/\/$1\">$1<\/a>/gi;
    push (@lines, $line);
  }
  return @lines;
}

################################################################################
# Find next and prior Pages, used one HTML View
sub NavigatePages {
    my $self = shift;

    my $mFound = 0;
    my $sFound = 0;
    $self->{toppage} = 0;
    $self->{page_prev} = 0;
    $self->{page_next} = 0;
    $self->{subpage_prev} = 0;
    $self->{subpage_next} = 0;

    $self->{toppage} = $self->{INDEX}->[0][0] if ($self->{INDEX} && scalar ($self->{INDEX}));

# Outer Mainpages-Loop##########################################################
    foreach my $p (@{$self->{INDEX}}) {
       if($mFound == 1) {
            $self->{page_next} = $p->[0];
            last;
       }
       if($p->[0] && $p->[0] == $self->{mainpage}) {
            $mFound = 1;
            if ($p->[1] && scalar @{$p->[1]} > 1) {
# Inner Subpages-Loop###########################################################
                foreach my $s (@{$p->[1]}) {
                   if($sFound == 1) {
                        $self->{subpage_next} = sprintf ("%03d_%02d", $self->{mainpage},$s);
                        last;
                   }
                   if($s == $self->{subpage}) {
                        $sFound = 1;
                   }
                   if($sFound == 0) {
                       $self->{subpage_prev} = sprintf ("%03d_%02d", $self->{mainpage},$s);
                   }
                }
                if($sFound == 0) {
                    $self->{subpage_prev} = 0;
                }
# Inner Subpages-Loop###########################################################
            }
       }
       if($mFound == 0) {
           $self->{page_prev} = $p->[0];
       }
    }
    if($mFound == 0) {
        $self->{page_prev} = 0;
    }
# Outer Mainpages-Loop##########################################################
}

################################################################################
# Our internal real page deliverer
sub realpage {
  my $self    = shift || return error ('No Object!');
  my $console = shift || return error ('No Console!');
  my $mainpage= shift || return error ('No Page!');
  my $subpage = shift || return error ('No Subpage!');
  my $bHTML = shift;

  my $basedir = $self->{dir} || return error ('No directory is defined!');
  my $chandir  = $self->{CHANNELDIR} || return error ('No CHANNEL');
  my $cache = $self->{cache} || 'packed';
################################################################################
# get filename
  my $filename;
  if ($cache eq 'packed') {
    # Build name /vtx/S19.2E-1-1101-28108/100s.vtx
    my $group = (int ($mainpage / 10)) *10;
    $filename = sprintf ("%s/%s/%03ds.vtx", $basedir, $chandir, $group);
  } else {
    # Build name /vtx/15/100_01.vtx
    $filename = sprintf ("%s/%s/%03d_%02d.vtx", $basedir, $chandir, $mainpage, $subpage);
  }
################################################################################
# Now open and read this file
  my $fh = FileHandle->new;
  if(!$fh->open($filename)) {
      $self->pagedump($console,gettext("The page could not be found!"),"");
      return "";
  }

  my $result = $self->readpage($console, $fh, $mainpage, $subpage, $bHTML);
  $fh->close();
  return $result;
}

################################################################################
# Translation table for ASCII
# Source - Bytelayout - vdr-plugin osdteletext-0.4.1/txtfont.c
# Codingrule iso-8859-15
my @tableascii = (
    ' ', # 0x20
    '!', # 0x21
    '"', # 0x22
    '#', # 0x23
    '$', # 0x24
    '%', # 0x25
    '&', # 0x26
    '\'', # 0x27
    '(', # 0x28
    ')', # 0x29
    '*', # 0x2A
    '+', # 0x2B
    ',', # 0x2C
    '-', # 0x2D
    '.', # 0x2E
    '/', # 0x2E
    '0', # 0x30
    '1', # 0x31
    '2', # 0x32
    '3', # 0x33
    '4', # 0x34
    '5', # 0x35
    '6', # 0x36
    '7', # 0x37
    '8', # 0x38
    '9', # 0x39
    ':', # 0x3A
    ';', # 0x3B
    '<', # 0x3C
    '=', # 0x3D
    '>', # 0x3E
    '?', # 0x3F
    '§', # 0x40
    'A', # 0x41
    'B', # 0x42
    'C', # 0x43
    'D', # 0x44
    'E', # 0x45
    'F', # 0x46
    'G', # 0x47
    'H', # 0x48
    'I', # 0x49
    'J', # 0x4A
    'K', # 0x4B
    'L', # 0x4C
    'M', # 0x4D
    'N', # 0x4E
    'O', # 0x4F
    'P', # 0x50
    'Q', # 0x51
    'R', # 0x52
    'S', # 0x53
    'T', # 0x54
    'U', # 0x55
    'V', # 0x56
    'W', # 0x57
    'X', # 0x58
    'Y', # 0x59
    'Z', # 0x5A
    'Ä', # 0x5B
    'Ö', # 0x5C
    'Ü', # 0x5D
    '^', # 0x5E
    '_', # 0x5F
    '°', # 0x60
    'a', # 0x61
    'b', # 0x62
    'c', # 0x63
    'd', # 0x64
    'e', # 0x65
    'f', # 0x66
    'g', # 0x67
    'h', # 0x68
    'i', # 0x69
    'j', # 0x6A
    'k', # 0x6B
    'l', # 0x6C
    'm', # 0x6D
    'n', # 0x6E
    'o', # 0x6F
    'p', # 0x70
    'q', # 0x71
    'r', # 0x72
    's', # 0x73
    't', # 0x74
    'u', # 0x75
    'v', # 0x76
    'w', # 0x77
    'x', # 0x78
    'y', # 0x79
    'z', # 0x7A
    'ä', # 0x7B
    'ö', # 0x7C
    'ü', # 0x7D
    'ß', #/0x7E
    ' ', # Block 0x7F
    '@', # 0x80
    ' ', # 0x81
    ' ', # 0x82
    '£', # 0x83
    '$', # 0x84
    ' ', # 0x85
    ' ', # 0x86
    ' ', # 0x87
    ' ', # 0x88
    ' ', # 0x89
    ' ', # 0x8A
    ' ', # 0x8B
    ' ', # 0x8C
    ' ', # 0x8D
    ' ', # 0x8E
    '#', # 0x8F
    'É', # 0x90
    'é', # 0x91
    'ä', # 0x92
    '#', # 0x93
    ' ', # 0x94
    ' ', # 0x95
    ' ', # 0x96
    ' ', # 0x97
    'ö', # 0x98
    'å', # 0x99
    'ü', # 0x9A
    'Ä', # 0x9B
    'Ö', # 0x9C
    'Å', # 0x9D
    'Ü', # 0x9E
    '_', # 0x9F
    ' ', # 0x20a  0xA0
    ' ', # 0x21a  0xA1
    ' ', # 0x22a  0xA2
    ' ', # 0x23a  0xA3
    ' ', # 0x24a  0xA4
    ' ', # 0x25a  0xA5
    ' ', # 0x26a  0xA6
    ' ', # 0x27a  0xA7
    ' ', # 0x28a  0xA8
    ' ', # 0x29a  0xA9
    ' ', # 0x2Aa  0xAA
    ' ', # 0x2Ba  0xAB
    ' ', # 0x2Ca  0xAC
    ' ', # 0x2Da  0xAD
    ' ', # 0x2Ea  0xAE
    ' ', # 0x2Fa  0xAF
    ' ', # 0x30a  0xB0
    ' ', # 0x31a  0xB1
    ' ', # 0x32a  0xB2
    ' ', # 0x33a  0xB3
    ' ', # 0x34a  0xB4
    ' ', # 0x35a  0xB5
    ' ', # 0x36a  0xB6
    ' ', # 0x37a  0xB7
    ' ', # 0x38a  0xB8
    ' ', # 0x39a  0xB9
    ' ', # 0x3Aa  0xBA
    ' ', # 0x3Ba  0xBB
    ' ', # 0x3Ca  0xBC
    ' ', # 0x3Da  0xBD
    ' ', # 0x3Ea  0xBE
    ' ', # 0x3Fa  0xBF
    'é', # 0xC0
    'ù', # 0xC1
    'à', # 0xC2
    '£', # 0xC3
    '$', # 0xC4
    'ã', # 0xC5
    'õ', # 0xC6
    ' ', # 0xC7
    'ò', # 0xC8
    'è', # 0xC9
    'ì', # 0xCA
    '°', # 0xCB
    'ç', # 0xCC
    ' ', # 0xCD
    ' ', # 0xCE
    '#', # 0xCF
    'à', # 0xD0
    'è', # 0xD1
    'â', # 0xD2
    'é', # 0xD3
    'ï', # 0xD4
    'Ã', # 0xD5
    'Õ', # 0xD6
    'Ç', # 0xD7
    'ô', # 0xD8
    'û', # 0xD9
    'ç', # 0xDA
    'ë', # 0xDB
    'ê', # 0xDC
    'ù', # 0xDD
    'î', # 0xDE
    '#', # 0xDF
    '¡', # 0xE0
    '¿', # 0xE1
    'ü', # 0xE2
    'ç', # 0xE3
    '$', # 0xE4
    ' ', # 0xE5
    ' ', # 0xE6
    ' ', # 0xE7
    'ñ', # 0xE8
    'è', # 0xE9
    'à', # 0xEA
    'á', # 0xEB
    'é', # 0xEC
    'í', # 0xED
    'ó', # 0xEE
    'ú', # 0xEF
    'Á', # 0xF0
    'À', # 0xF1
    'È', # 0xF2
    'Í', # 0xF3
    'Ï', # 0xF4
    'Ó', # 0xF5
    'Ò', # 0xF6
    'Ú', # 0xF7
    'æ', # 0xF8
    'Æ', # 0xF9
    'ð', # 0xFA
    ' ', # 0xFB
    'ø', # 0xFC
    'Ø', # 0xFD
    ' ', # 0xFE
    ' ', # 0xFF
    ' ', # 0x60a
    ' ', # 0x61a
    ' ', # 0x62a
    ' ', # 0x63a
    ' ', # 0x64a
    ' ', # 0x65a
    ' ', # 0x66a
    ' ', # 0x67a
    ' ', # 0x68a
    ' ', # 0x69a
    ' ', # 0x6Aa
    ' ', # 0x6Ba
    ' ', # 0x6Ca
    ' ', # 0x6Da
    ' ', # 0x6Ea
    ' ', # 0x6Fa
    ' ', # 0x70a
    ' ', # 0x71a
    ' ', # 0x72a
    ' ', # 0x73a
    ' ', # 0x74a
    ' ', # 0x75a
    ' ', # 0x76a
    ' ', # 0x77a
    ' ', # 0x78a
    ' ', # 0x79a
    ' ', # 0x7Aa
    ' ', # 0x7Ba
    ' ', # 0x7Ca
    ' ', # 0x7Da
    ' ', # 0x7Ea
    ' '  # 0x7Fa
);

################################################################################
# Translation table for HTML
my @tablehtml = (
    ' ', # 0x20
    '!', # 0x21
    '"', # 0x22
    '#', # 0x23
    '$', # 0x24
    '%', # 0x25
    '&amp;', # 0x26
    '\'', # 0x27
    '(', # 0x28
    ')', # 0x29
    '*', # 0x2A
    '+', # 0x2B
    ',', # 0x2C
    '-', # 0x2D
    '.', # 0x2E
    '/', # 0x2E
    '0', # 0x30
    '1', # 0x31
    '2', # 0x32
    '3', # 0x33
    '4', # 0x34
    '5', # 0x35
    '6', # 0x36
    '7', # 0x37
    '8', # 0x38
    '9', # 0x39
    ':', # 0x3A
    ';', # 0x3B
    '&lt;', # 0x3C
    '=', # 0x3D
    '&gt;', # 0x3E
    '?', # 0x3F
    '&sect;', # 0x40
    'A', # 0x41
    'B', # 0x42
    'C', # 0x43
    'D', # 0x44
    'E', # 0x45
    'F', # 0x46
    'G', # 0x47
    'H', # 0x48
    'I', # 0x49
    'J', # 0x4A
    'K', # 0x4B
    'L', # 0x4C
    'M', # 0x4D
    'N', # 0x4E
    'O', # 0x4F
    'P', # 0x50
    'Q', # 0x51
    'R', # 0x52
    'S', # 0x53
    'T', # 0x54
    'U', # 0x55
    'V', # 0x56
    'W', # 0x57
    'X', # 0x58
    'Y', # 0x59
    'Z', # 0x5A
    '&Auml;', # 0x5B
    '&Ouml;', # 0x5C
    '&Uuml;', # 0x5D
    '^', # 0x5E
    '_', # 0x5F
    '&deg;', # 0x60
    'a', # 0x61
    'b', # 0x62
    'c', # 0x63
    'd', # 0x64
    'e', # 0x65
    'f', # 0x66
    'g', # 0x67
    'h', # 0x68
    'i', # 0x69
    'j', # 0x6A
    'k', # 0x6B
    'l', # 0x6C
    'm', # 0x6D
    'n', # 0x6E
    'o', # 0x6F
    'p', # 0x70
    'q', # 0x71
    'r', # 0x72
    's', # 0x73
    't', # 0x74
    'u', # 0x75
    'v', # 0x76
    'w', # 0x77
    'x', # 0x78
    'y', # 0x79
    'z', # 0x7A
    '&auml;', # 0x7B
    '&ouml;', # 0x7C
    '&uuml;', # 0x7D
    '&szlig;', # 0x7E
    'image-7F', # Block 0x7F
    '@', # 0x80
    '&ndash;', # 0x81
    '&frac14;', # 0x82 1/4
    '&pound;', # 0x83
    '$', # 0x84
    ' ', # 0x85 Taste Teletext (a)
    ' ', # 0x86 Taste Small
    ' ', # 0x87 Taste Hide
    ' ', # 0x88 ||
    '&frac34;', # 0x89 3/4
    '&divide;', # 0x8A
    '&larr;', # 0x8B  <-
    '&frac12;', # 0x8C 1/2
    '&rarr;', # 0x8D ->
    '&uarr;', # 0x8E
    '#', # 0x8F
    '&Eacute;', # 0x90
    '&eacute;', # 0x91
    '&auml;', # 0x92
    '#', # 0x93
    '&curren;', # 0x94
    ' ', # 0x95 Taste Teletext (b)
    ' ', # 0x96 Taste
    ' ', # 0x97 Taste Big
    '&ouml;', # 0x98
    '&aring;', # 0x99
    '&uuml;', # 0x9A
    '&Auml;', # 0x9B
    '&Ouml;', # 0x9C
    '&Aring;', # 0x9D
    '&Uuml;', # 0x9E
    '_', # 0x9F
    'image-20', # 0x20a  0xA0 # image-20 == whitespace
    'image-21', # 0x21a  0xA1
    'image-22', # 0x22a  0xA2
    'image-23', # 0x23a  0xA3
    'image-24', # 0x24a  0xA4
    'image-25', # 0x25a  0xA5
    'image-26', # 0x26a  0xA6
    'image-27', # 0x27a  0xA7
    'image-28', # 0x28a  0xA8
    'image-29', # 0x29a  0xA9
    'image-2A', # 0x2Aa  0xAA
    'image-2B', # 0x2Ba  0xAB
    'image-2C', # 0x2Ca  0xAC
    'image-2D', # 0x2Da  0xAD
    'image-2E', # 0x2Ea  0xAE
    'image-2F', # 0x2Fa  0xAF
    'image-30', # 0x30a  0xB0
    'image-31', # 0x31a  0xB1
    'image-32', # 0x32a  0xB2
    'image-33', # 0x33a  0xB3
    'image-34', # 0x34a  0xB4
    'image-35', # 0x35a  0xB5
    'image-36', # 0x36a  0xB6
    'image-37', # 0x37a  0xB7
    'image-38', # 0x38a  0xB8
    'image-39', # 0x39a  0xB9
    'image-3A', # 0x3Aa  0xBA
    'image-3B', # 0x3Ba  0xBB
    'image-3C', # 0x3Ca  0xBC
    'image-3D', # 0x3Da  0xBD
    'image-3E', # 0x3Ea  0xBE
    'image-3F', # 0x3Fa  0xBF
    '&eacute;', # 0xC0
    '&ugrave;', # 0xC1
    '&agrave;', # 0xC2
    '&pound;', # 0xC3
    '$', # 0xC4
    '&atilde;', # 0xC5
    '&otilde;', # 0xC6
    '&bull;', # 0xC7
    '&ograve;', # 0xC8
    '&egrave;', # 0xC9
    '&igrave;', # 0xCA
    '&deg;', # 0xCB
    '&ccedil;', # 0xCC
    '&rarr;', # 0xCD
    '&uarr;', # 0xCE
    '#', # 0xCF
    '&agrave;', # 0xD0
    '&egrave;', # 0xD1
    '&acirc;', # 0xD2
    '&eacute;', # 0xD3
    '&iuml;', # 0xD4
    '&Atilde;', # 0xD5
    '&Otilde;', # 0xD6
    '&Ccedil;', # 0xD7
    '&ocirc;', # 0xD8
    '&ucirc;', # 0xD9
    '&ccedil;', # 0xDA
    '&euml;', # 0xDB
    '&ecirc;', # 0xDC
    '&ugrave;', # 0xDD
    '&icirc;', # 0xDE
    '#', # 0xDF
    '&iexcl;', # 0xE0
    '&iquest;', # 0xE1
    '&uuml;', # 0xE2
    '&ccedil;', # 0xE3
    '$', # 0xE4
    ' ', # 0xE5 a mit unterstrich
    ' ', # 0xE6 o mit unterstrich
    '&Ntilde;', # 0xE7
    '&ntilde;', # 0xE8
    '&egrave;', # 0xE9
    '&agrave;', # 0xEA
    '&aacute;', # 0xEB
    '&eacute;', # 0xEC
    '&iacute;', # 0xED
    '&oacute;', # 0xEE
    '&uacute;', # 0xEF
    '&Aacute;', # 0xF0
    '&Agrave;', # 0xF1
    '&Egrave;', # 0xF2
    '&Iacute;', # 0xF3
    '&Iuml;', # 0xF4
    '&Oacute;', # 0xF5
    '&Ograve;', # 0xF6
    '&Uacute;', # 0xF7
    '&aelig;', # 0xF8
    '&AElig;', # 0xF9
    '&eth;', # 0xFA
    '&ETH;', # 0xFB
    '&oslash;', # 0xFC
    '&Oslash;', # 0xFD
    '&thorn;', # 0xFE
    '&THORN;', # 0xFF
    'image-60', # 0x60a
    'image-61', # 0x61a
    'image-62', # 0x62a
    'image-63', # 0x63a
    'image-64', # 0x64a
    'image-65', # 0x65a
    'image-66', # 0x66a
    'image-67', # 0x67a
    'image-68', # 0x68a
    'image-69', # 0x69a
    'image-6A', # 0x6Aa
    'image-6B', # 0x6Ba
    'image-6C', # 0x6Ca
    'image-6D', # 0x6Da
    'image-6E', # 0x6Ea
    'image-6F', # 0x6Fa
    'image-70', # 0x70a
    'image-71', # 0x71a
    'image-72', # 0x72a
    'image-73', # 0x73a
    'image-74', # 0x74a
    'image-75', # 0x75a
    'image-76', # 0x76a
    'image-77', # 0x77a
    'image-78', # 0x78a
    'image-79', # 0x79a
    'image-7A', # 0x7Aa
    'image-7B', # 0x7Ba
    'image-7C', # 0x7Ca
    'image-7D', # 0x7Da
    'image-7E', # 0x7Ea
    'image-7F'  # 0x7Fa
);

################################################################################
# Color table
my @colors = (
    "black", "red", "green", "yellow",
    "blue", "magenta", "cyan", "white"
);

################################################################################
# Translation unpacked bytes to text
sub translate {

    my $self=shift;
    my $bHTML=shift;
    my $c=shift;
    my $graph=shift;
    my $double=shift;
    my $sepgraph=shift;
    my $fg=shift;
    my $bg=shift;
    $c = int($c);
    if ($graph == 1) {
        if (($c>=0x20) and ($c<=0x3F)) { $c += 0x80; }
        elsif (($c>=0x60) and ($c<=0x7F)) { $c += 0xA0; }
    }
    $c -= 0x20;
    if($bHTML == 1) {
        my $result;

        if ($fg != $self->{ofg} or $bg != $self->{obg}) {
            if ($self->{ofg} != -1 or $self->{obg} != -1) {
                $result .= "</font>";
            }
            $result .= sprintf("<font style=\"color:%s;background-color:%s;\">",$colors[$fg],$colors[$bg]);

            $self->{ofg} = $fg;
            $self->{obg} = $bg;
        }
        if($c < 0 or $c > 256) {
            $result .= '&nbsp;';
        } else {
            my $h .= $tablehtml[$c];
            $h =~ s/ /"&nbsp;"/eg;
            $result .= $h;
            if ($graph == 1 || $c == 0x5f) #Block 0x5f = 0x7f - 0x20
            {
                my $pre = "<img class=\"vtx\" src=\"vtximages/";
                my $color = $colors[$fg];
                my $post = ".gif\" alt=\"\" title=\"\" />&nbsp;";
                # set <img class="vtx" class="vtx" src="vtximages/black21.gif" alt="" title="">
                # vtx-image are locate inside skin folder
                $result =~ s/(image)\-(.+)/$pre.$color.$2.$post/eg;
            }
        }
        return $result;
    } else {
        return ' ' if($c < 0 or $c > 256);
        return $tableascii[$c];
    }
}
################################################################################
# close text line
sub endline {
    my $self=shift;
    my $bHTML=shift;
    my $result = "";
    $result .= "</font><br />" if($bHTML);
    $result .= "\n";
    return $result;
}

################################################################################
# Read page which open from filehandle
sub readpage {
    my $self=shift;
    my $console=shift;
    my $fh=shift;
    my $mainpage=shift;
    my $subpage=shift;
    my $bHTML = shift;
    my $cache = $self->{cache} || 'packed';

# Seek inside packed file
    if ($cache eq 'packed') {
        # Parse TOC
        #
        # 8x[MAIN,SUB a 2x4byte],
        # 8x[PAGE a 972byte],
        # 8x[MAIN,SUB a 2x4byte],
        # 8x[PAGE a 972byte]
        #
        my $tocbuf;
        my $notfound = 1;
        while($notfound == 1) {
            if($fh->read($tocbuf, 4*2*8) ne 64) {
                $self->pagedump($console,gettext("The page could not readed!"),"");
                return "";
            }
            my @toc = unpack( "i*", $tocbuf);
            my $n = 0;
            for (;$n < 8 and $notfound == 1; ++$n ) {
                my $mpage = int(sprintf ("%X",@toc[$n*2]));
                my $spage = int(sprintf ("%X",@toc[($n*2)+1]));
                # Check for last toc entry 0/0
                if($mpage == 0 and $spage == 0) {
                    $self->pagedump($console,gettext("The page could not be found!"),"");
                    return "";
                }
                # Look for toc entry same wanted page
                if($mpage == $mainpage) {
                    if(($spage == $subpage )
                      or ($subpage <= 1 and $spage <= 1))  {

                    $self->{mainpage} = $mpage;
                    $self->{subpage} = $spage;

                    $notfound = 0;
                    }
                }
            }
            --$n if($notfound == 0);
            # Skip unwanted Pages
            if(0 == $fh->seek((972*$n), 1)) {
                $self->pagedump($console,gettext("The page could not readed!"),"");
                return "";
            }
        }
    } else {
        $self->{mainpage} = $mainpage;
        $self->{subpage} = $subpage;
    }

# Read page now
    my $packed;
    if($fh->read($packed, 972) ne 972) {
        $self->pagedump($console,gettext("The page could not readed!"),"");
        return "";
    }
    my $result = "";
    $result .= "<p class=\"vtx\">\n" if($bHTML);

    my @buf = unpack( "C*", $packed);

    my $n = 9 + 1 + 2; #Index, skip irgendwas davor, Language, irgendwas wieder
    my $flash=0;
    my $double=0;
    my $hidden=0; #hidden = verdeckt!!!
    my $sepgraph=0;
    my $hold=0;
    my $graph=0;
    my $skipnextline=0;
    my $lc=0x20;

    my $fg = 7;
    my $bg = 0;
    for (my $y=0;$y<24;$y++) {

         $flash=0;
         $double=0;
         $hidden=0; #hidden = verdeckt!!!
         $sepgraph=0;
         $hold=0;
         $graph=0;
         $skipnextline=0;
         $lc=0x20;

         $fg = 7;
         $bg = 0;
         $self->{ofg} = -1;
         $self->{obg} = -1;

         for (my $x=0;$x<40;++$x,++$n)
         {
#            $result .= sprintf("<!-- %2x -->",$buf[$n])
#              if($bHTML);

            my $c=int($buf[$n] & 0x7F); #Parity Bit ist uninteressant!

            if (($y==0)&&($x<8)) { # Die Daten sind uninteressant zur Anzeige!
               $c = 0x20;
            }

            if( $c >= 0x00 and $c <=  0x07 ) {
                        $lc=0x20
                          if($graph);
                        $hidden= 0;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);
                        $graph= 0;
                        $fg = int($c);

            } elsif( $c == 0x08 ) { # Blinken einschalten (flashing)
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);
                        $flash= 1;

            } elsif( $c == 0x09 ) { # Blinken ausschalten (steady)
                        $flash= 0;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);
            } elsif( $c == 0x0A ) { # end box (nicht benutzt)
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x0B ) { # start box (nicht benutzt)
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x0C ) { # normal high
                        $double= 0;
                        $lc=0x20;
                        $result .= $self->translate($bHTML, 0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x0D ) { # double high
#                     for (my $frei=1;$frei<40;$frei++)
#                          $result .= $self->translate($bHTML, $frei,$y+1,0x20,$graph,$double,$sepgraph,$fg,$bg);
#                       $result .= $self->endline($bHTML);

                        $result .= $self->translate($bHTML, 0x20,$graph,$double,$sepgraph,$fg,$bg);
                        $double= 1;
#                      $skipnextline= 1;

            } elsif( $c >= 0x0E and $c <=  0x0F ) { # keine Funktion

            } elsif( $c >= 0x10 and $c <=  0x17 ) { #
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);
                        $hidden= 0;
                        $graph= 1;
                        $fg = $c-0x10;

            } elsif( $c == 0x18 ) { # verborgen
                        $hidden= 1;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x19 ) { # contigouous graphics
                        $sepgraph= 0;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x1A ) { # separated grphics
                        $sepgraph= 1;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x1B ) { # ESC

            } elsif( $c == 0x1C ) { # black background
                        $bg = (0);
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x1D ) { # new background
                        my $tmp = $fg; # ExchangeColor
                        $fg = $bg;
                        $bg = $tmp;

                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x1E ) { # hold graphics
                        $hold= 1;
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);

            } elsif( $c == 0x1F ) { # release graphics
                        $result .= $self->translate($bHTML, ($hold == 1)?$lc:0x20,$graph,$double,$sepgraph,$fg,$bg);
                        $hold= 0;

            } else { #
                  if ($graph == 1) {
                      $lc = $c;
                  }
                  $result .= $self->translate($bHTML, $c,$graph,$double,$sepgraph,$fg,$bg);
            }
         }
         $result .= $self->endline($bHTML);
         if ($skipnextline==1) {
               $y++;
         }
    }
    $result .= "</p>\n" if($bHTML);
    return $result;
}

################################################################################
# Read TOC from packed file for index
sub GetPackedToc {

    my $filename = shift;
    my @index;
    my $fh = FileHandle->new;
    if(!$fh->open($filename)) {
        error ("The page could not be found! : $filename");
    } else {
        # Parse TOC
        #
        # 8x[MAIN,SUB a 2x4byte],
        # 8x[PAGE a 972byte],
        # 8x[MAIN,SUB a 2x4byte],
        # 8x[PAGE a 972byte]
        #
        my $tocbuf;
        my $bEnd = 0;
        while(!$fh->eof() and    $bEnd == 0) {
            if($fh->read($tocbuf, 4*2*8) ne 64) {
                $bEnd = 1;
                last;
            }
            my @toc = unpack( "i*", $tocbuf);
            my $n = 0;
            for (;$n < 8; ++$n ) {
                my $m = (sprintf ("%X",@toc[$n*2]));

                next # Skip nonregular pages like 80F
                    if($m =~ /\D/sig);

                my $mpage = int($m);
                my $spage = int(sprintf ("%X",@toc[($n*2)+1]));

                # Check for last toc entry 0/0
                if($mpage == 0 and $spage == 0) {
                    $bEnd = 1;
                    last;
                }
                my $found = 0;
                foreach my $p (@index) {
                    if($p->[0] == $mpage) {
                        $found = 1;
                        push(@{$p->[1]},$spage)
                            if($spage != 0);
                        last;
                    }
                }
                if ($found == 0) {
                    push(@index,[$mpage, [$spage] ]);
                }
            }
            # Skip Pages
            if(0 == $fh->seek((972*8), 1)) {
                $bEnd = 1;
                last;
            }
        }

        $fh->close();
    }
    return @index;
}

################################################################################
# HighLight searched text
sub HighLight {

    my $self = shift;
    my $result = shift;
    my $search = shift;
    my $lines;

    my $ua = "<font style=\"color:black;background-color:lime;\">";
    my $ub = "</font>";

    foreach my $line (split('\n',$result)) {
        $line =~ s/$search/$ua$search$ub/g;
        $lines .= $line;
    }
    return $lines;
}

################################################################################
# Callback "Teletext search"
sub search {
    my $self = shift || return error ('No Object!');
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $search = shift;

    my $channel = $self->{CHANNEL};
    my $chandir  = $self->{CHANNELDIR};
    if($channel eq "" or $chandir eq "") {
        $self->pagedump($console,gettext("No channel defined!"),"");
    }

    chomp($search);
    unless($search) {
        $self->pagedump($console,gettext("No data to search given!"),$chandir);
    }

    my $oldpage = $self->{mainpage};
    my $oldsubpage = $self->{subpage};

    my @foundlist;
    my $searchlimit = 25;
    foreach my $p (@{$self->{INDEX}}) {
        foreach my $s (@{$p->[1]}) {
            my $mp = sprintf("%3d",$p->[0]);
            my $sp = sprintf("%2d",$s);

            my $lookup = $self->realpage($console, $mp, $sp, 0);

            my @found = grep(/$search/,$lookup);
            if(scalar @found > 0) {
                push(@foundlist,[$mp, $sp]);
                $searchlimit--;
                last if($searchlimit <= 0);
            }
         }
         last if($searchlimit <= 0);
    }

    if(scalar @foundlist < 1) {
        $self->{mainpage} = $oldpage;
        $self->{subpage} = $oldsubpage;
        $self->pagedump($console,sprintf(gettext("No page with \'%s\' found!"),$search),$chandir);
        return 0;
    }

    my $bHTML = ($console->{TYP} ne 'HTML')?0:1;
    foreach my $pp (@foundlist) {

            $self->{mainpage} = $pp->[0];
            $self->{subpage} = $pp->[1];

            my $result = $self->realpage($console, $pp->[0], $pp->[1],$bHTML);

            if($bHTML) {
              $result = $self->HighLight($result,$search);
            }

            $self->pagedump($console,$result,$chandir)
              if($result ne "");
    }
    return 1;
}

1;
