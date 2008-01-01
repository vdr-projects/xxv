package XXV::MODULES::STREAM;
use strict;

use Tools;
use Locale::gettext;
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
            streamtyp => {
                description => gettext('Typ of streaming'),
                default     => 1,
                type        => 'list',
                choices     => sub {
                                    my $erg = $obj->_get_streamtyp();
                                    map { my $x = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $x; } @$erg;
                                    return @$erg;
                                 },
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    my $erg = $obj->_get_streamtyp();
                    unless($value >= $erg->[0]->[0] and $value <= $erg->[-1]->[0]) {
                        return undef, 
                               sprintf(gettext('Sorry, but value must be between %d and %d'),
                                  $erg->[0]->[0],$erg->[-1]->[0]);
                    }
                    return $value;
                },
            },
            netvideo => {
                description => gettext('Base directory of remote SMB/NFS share.'),
                default     => '\\\\vdr\\video',
                type        => 'string',
            },
            mimetyp => {
                description => gettext('Used mime type to deliver video streams'),
                default     => 'video/x-mpegurl',
                type        => 'string',
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
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your System:\nperl -MCPAN -e 'install $_'") if($@);
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

    return $console->err(gettext("Can't stream files!"))
      unless($console->can('datei'));

    my $cmod = main::getModule('CHANNELS');

    my $ch = $cmod->ToCID($channel);
    return $console->err(sprintf(gettext("This channel '%s' does not exist!"),$channel))
      unless($ch);

    my $cpos = $cmod->ChannelToPos($ch);
    debug sprintf('Live stream with channel "%s"%s',
        $cmod->ChannelToName($ch),
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    $console->{nopack} = 1;

    my $data;
    $data = "#EXTM3U\r\n";
    $data .= sprintf("http://%s:3000/PES/%d", $obj->{host}, $cpos);
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
    my $videopath = $rmod->{videodir};
    my $path = $rmod->IdToPath($recid)
        or return $console->err(gettext(sprintf("Couldn't find recording: '%s'", $recid)));

    my @files = bsd_glob("$path/[0-9][0-9][0-9].vdr");

    return $console->err(gettext(sprintf("Couldn't find recording: '%s'", $recid)))
      unless scalar(@files);

    my $start = 0;
    my $offset = 0;
    if($params && exists $params->{start}) {
      $start = &text2frame($params->{start});
    }
    if($start) {
      my ($filenumber,$fileoffset) = $rmod->frametofile($path,$start);
      splice(@files, 0, $filenumber-1) if($filenumber && ($filenumber - 1) > 0);
      $offset = $fileoffset if($fileoffset && ($fileoffset - 1) > 0);
    }

    debug sprintf('Play recording "%s"%s',
        $path,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    if($obj->{streamtyp} != 1) {
      return $console->err(gettext("Can't stream files!"))
        unless($console->can('stream'));

      return $console->stream(\@files, $obj->{mimetyp}, $offset);

    } else {

      return $console->err(gettext("Can't stream files!"))
        unless($console->can('datei'));

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

# ------------------
sub _get_streamtyp {
# ------------------
    my $obj = shift || return error('No object defined!');

    return [
            [ 1, gettext('Remote SMB/NFS share') ],
            [ 2, gettext('HTTP Streaming') ],
          ];
}
1;
