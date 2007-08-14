package XXV::MODULES::STREAM;
use strict;

use Tools;
use Locale::gettext;
use File::Basename;
use File::Find;
use File::Path;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'STREAM',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module generate streams from recordings.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Preferences => {
            host => {
                description => gettext('Used host of referred link inside playlist.'),
                default     => 'localhost',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            netvideo => {
                description => gettext('Path from remote video directory (SambaDir).'),
                default     => '\\\\vdr\\video',
                type        => 'string',
            },
            mimetyp => {
                description => gettext('Used mime-typ to deliver video streams.'),
                default     => 'video/x-mpegurl',
                type        => 'string',
            },
        },
        Commands => {
            playrecord => {
                description => gettext("Play the record over samba or nfs."),
                short       => 'pre',
                callback    => sub{ $obj->play_record(@_) },
                DenyClass   => 'stream',
            },
            livestream => {
                description => gettext("Stream a channel 'cid'. This required the streamdev plugin!"),
                short       => 'lst',
                callback    => sub{ $obj->live_stream(@_) },
                DenyClass   => 'stream',
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

    # The Initprocess
    my $erg = $self->init or return error('Problem to initialize module');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    1;
}


# ------------------
sub live_stream {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $channel = shift || return $console->err(gettext("No ChannelID to Stream! Please use livestream 'cid'"));

    debug sprintf('Call live stream with channel "%s"%s',
        $channel,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    if($channel && $console->typ eq 'HTML') {
        $console->{nocache} = 1;
        $console->{nopack} = 1;
        $console->{noFooter} = 1;

        my $data;
        $data = "#EXTM3U\r\n";
        $data .= sprintf("http://%s:3000/PES/%d", $obj->{host}, $channel);
        $data .= "\r\n";
         
        my $arg;
        $arg->{'attachment'} = sprintf("livestream%d.m3u", $channel);
        $arg->{'Content-Length'} = length($data);

        $console->out($data, $obj->{mimetyp}, %{$arg} );
    } else {
      $console->err(gettext("Sorry, stream is'nt supported"));
    }
}

# ------------------
sub play_record {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $recid   = shift || return $console->err(gettext("No RecordID to Play! Please use rplay 'rid'"));

    my $rmod = main::getModule('RECORDS');
    my $videopath = $rmod->{videodir};
    my $path = $rmod->IdToPath($recid)
        or return $console->err(gettext(sprintf('I can\'t found recid: %s', $recid)));

    debug sprintf('Call play record "%s"%s',
        $path,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    my $data;
    $data = "#EXTM3U\r\n";
    foreach my $file (glob("$path/???.vdr")) {
        $file =~ s/^$videopath//si;
        $file =~ s/^[\/|\\]//si;
        my $URL = sprintf("%s/%s\r\n", $obj->{netvideo}, $file);
        $URL =~s/\//\\/g
            if($URL =~ /^\\\\/sig              # Samba \\host/xxx/yyy => \\host\xxx\yyy
            || $URL =~ /^[a-z]\:[\/|\\]/sig);  # Samba x:/xxx/yyy => x:\xxx\yyy
        $data .= $URL;
    }

    if($data && $console->typ eq 'HTML') {
        $console->{nocache} = 1;
        $console->{nopack} = 1;
        $console->{noFooter} = 1;

        my $arg;
        $arg->{'attachment'} = sprintf("playrecord%d.m3u", $recid);
        $arg->{'Content-Length'} = length($data);

        $console->out($data, $obj->{mimetyp}, %{$arg} );
    } else {
      $console->err(gettext("Sorry, stream is'nt supported"));
    }
}
1;
