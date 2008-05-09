package XXV::MODULES::STREAM;
use strict;

use Tools;
use File::Basename;
use File::Find;
use File::Path;
use File::Glob ':glob';

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'STREAM',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module generate streams from recordings.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            host => {
                description => gettext('Used host of referred link inside playlist.'),
                default     => 'localhost',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            method => {
                description => gettext('Typ of streaming'),
                default     => 'http',
                type        => 'list',
                choices     => [
                    [ gettext('HTTP Streaming'),      'http' ],
                    [ gettext('Remote SMB/NFS share'),'smb' ],
                ],
                required    => gettext('This is required!'),
            },
            mimetyp => {
                description => gettext('Used mime type to deliver video streams'),
                default     => 'video/x-mpegurl',
                type        => 'string',
            },
            netvideo => {
                description => gettext('Base directory of remote SMB/NFS share.'),
                default     => '\\\\vdr\\video',
                type        => 'string',
            },
            widget => {
                description => gettext('Used stream widget'),
                type        => 'list',
                default     => 'vlc',
                choices     => [
                    [gettext("Other external player"), 'external'],
                    [gettext('Embed media player'),    'media'],
                    [gettext('Embed vlc player'),      'vlc'],
                ],
                required    => gettext("This is required!"),
            },
            streamtype => {
                description => gettext('Used live stream type'),
                type        => 'list',
                default     => 'PES',
                choices     => [
                    [gettext("TS - Transport Stream"),  'TS'],
                    [gettext('PS - Program Stream'),    'PS'],
                    [gettext('PES - Packetized Elementary Stream'),      'PES'],
                    [gettext('ES - Elementary Stream'),  'ES'],
                    [gettext('External stream type'),    'Extern'],
                ],
                required    => gettext("This is required!"),
            },
            width => {
                description => gettext('Stream widget width'),
                default     => 720,
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
            height => {
                description => gettext('Stream widget height'),
                default     => 576,
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
        },
        Commands => {
            playrecord => {
                description => gettext("Stream a recordings."),
                short       => 'pre',
                callback    => sub{ $obj->playrecord(@_) },
                DenyClass   => 'stream',
                binary      => 'nocache'
            },
            livestream => {
                description => gettext("Stream a channel 'cid'. This required the streamdev plugin!"),
                short       => 'lst',
                callback    => sub{ $obj->livestream(@_) },
                DenyClass   => 'stream',
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

    # The Initprocess
    my $erg = $self->init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error('No object defined!');

    1;
}


# ------------------
sub livestream {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $channel = shift || return con_err($console,gettext("No channel defined for streaming!"));
    my $params  = shift;

    return $console->err(gettext("Can't stream files!"))
      unless($console->can('datei'));

    my $cmod = main::getModule('CHANNELS');

    my $ch = $cmod->ToCID($channel);
    return $console->err(sprintf(gettext("This channel '%s' does not exist!"),$channel))
      unless($ch);

    if($obj->{widget} ne 'external' && (!$params || !(exists $params->{player}))) {
      my $data = sprintf("?cmd=livestream&__player=1&data=%s",$ch);

      my $param = {
          title => $cmod->ChannelToName($ch),
          widget => $obj->{widget},
          width  => $obj->{width},
          height => $obj->{height},
      };
      return $console->player($data, $param);
    }

    my $cpos = $cmod->ChannelToPos($ch);
    debug sprintf('Live stream with channel "%s"%s',
        $cmod->ChannelToName($ch),
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    $console->{nopack} = 1;

    my $data;
    $data = "#EXTM3U\r\n";
    $data .= sprintf("http://%s:3000/%s/%d", $obj->{host},$obj->{streamtype}, $cpos);
    $data .= "\r\n";
     
    my $arg;
    $arg->{'attachment'} = sprintf("livestream-%s.m3u", $ch);
    $arg->{'Content-Length'} = length($data);

    return $console->out($data, $obj->{mimetyp}, %{$arg} );
}

# ------------------
sub playrecord {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recid   = shift || return $console->err(gettext("No recording defined for streaming!"));
    my $params  = shift;

    my $rmod = main::getModule('RECORDS');
    my $result = $rmod->IdToData($recid)
        or return $console->err(gettext(sprintf("Couldn't find recording: '%s'", $recid)));

    my $start = 0;
    my $offset = 0;
    if($params && exists $params->{start}) {
      $start = &text2frame($params->{start});
    }

    if($obj->{widget} ne 'external' && (!$params || !(exists $params->{player}))) {
      my $data = sprintf("?cmd=playrecord&__player=1&data=%s",$recid);
      $data .= sprintf("&__start=%d", $start) if($start);

      my $param = {
          title => $result->{title},
          widget => $obj->{widget},
          width  => $obj->{width},
          height => $obj->{height},
      };
      $param->{title} .= '~' . $result->{subtitle} if($result->{subtitle});

      return $console->player($data, $param);
    }

    return $console->err(gettext(sprintf("Couldn't find recording: '%s'", $recid)))
      unless $result->{Path};

    my $path = $result->{Path};
    my @files = bsd_glob("$path/[0-9][0-9][0-9].vdr");

    return $console->err(gettext(sprintf("Couldn't find recording: '%s'", $recid)))
      unless scalar(@files);

    if($start) {
      my ($filenumber,$fileoffset) = $rmod->frametofile($path,$start);
      splice(@files, 0, $filenumber-1) if($filenumber && ($filenumber - 1) > 0);
      $offset = $fileoffset if($fileoffset && ($fileoffset - 1) > 0);
    }

    debug sprintf('Play recording "%s"%s',
        $path,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    if($obj->{method} eq 'http') {
      return $console->err(gettext("Can't stream files!"))
        unless($console->can('stream'));

      return $console->stream(\@files, $obj->{mimetyp}, $offset);

    } else {

      return $console->err(gettext("Can't stream files!"))
        unless($console->can('datei'));

      my $videopath = $rmod->{videodir};

      my $data;
      $data = "#EXTM3U\r\n";
      foreach my $file (@files) {
        $file =~ s/^$videopath//si;
        $file =~ s/^[\/|\\]//si;
        my $URL = sprintf("%s/%s\r\n", $obj->{netvideo}, $file);
        $URL =~s/\//\\/g
        if($URL =~ /^\\\\/sig              # Samba \\host/xxx/yyy => \\host\xxx\yyy
        || $URL =~ /^[a-z]\:[\/|\\]/sig);  # Samba x:/xxx/yyy => x:\xxx\yyy
        $data .= $URL;
      }

      $console->{nopack} = 1;

      my $arg;
      $arg->{'attachment'} = sprintf("%s.m3u", $recid);
      $arg->{'Content-Length'} = length($data);

      return $console->out($data, $obj->{mimetyp}, %{$arg} );
    }
}

1;
