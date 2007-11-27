package XXV::MODULES::MUSIC;
use strict;

use Tools;
use Locale::gettext;
use File::Basename;
use File::Path;
use File::Find;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'MUSIC',
        Prereq => {
            'DBI'          => 'Database independent interface for Perl ',
            'DBD::mysql'   => 'MySQL driver for the Perl5 Database Interface (DBI)',
            'MP3::Icecast' => 'Generate Icecast streams, as well as M3U and PLSv2 playlists',
            'MP3::Info'    => 'Manipulate / fetch info from MP3 audio files ',
            'CGI'          => 'Simple Common Gateway Interface Class',
            'LWP::Simple'  => 'get, head, getprint, getstore, mirror - Procedural LWP interface',
            'Net::Amazon'  => 'Framework for accessing amazon.com via SOAP and XML/HTTP',
            'Net::Amazon::Request::Artist' =>
                              'Class for submitting Artist requests',
        },
        Description => gettext('This module managed music files.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $obj->status(@_) },
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            path => {
                description => gettext('Directory with the music files'),
                default     => '/music',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
            port => {
                description => gettext('Port to listen for icecast clients.'),
                default     => 8100,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            Interface => {
                description => gettext('Local interface to bind service'),
                default     => '0.0.0.0',
                type        => 'host',
                required    => gettext('This is required!'),
            },
            proxy => {
                description => gettext('Proxy URL to music server. e.g. (http://vdr/xxv) Please remember you must write the port to icecast server in your proxy configuration!'),
                default     => '',
                type        => 'string',
            },
            clients => {
                description => gettext('Maximum clients to connect at the same time'),
                default     => 5,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            coverimages => {
                description => gettext('Common directory for cover images'),
                default     => '/var/cache/xxv/cover',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
            muggle => {
                description => gettext('DSN for muggle database'),
                default     => 'DBI:mysql:database=GiantDisc;host=localhost;port=3306',
                type        => 'string',
                check       => sub{
                    my $value = shift;
                    $obj->{mdbh} = $obj->ConnectToMuggleDB($value);
                    return $value;
                },
            },
            mugglei => {
                description => sprintf(gettext("Path of command '%s'"),'mugglei'),
                default     => 'mugglei',
                type        => 'file',
            },
        },
        Commands => {
            mrefresh => {
                description => gettext('Rereading of the music directory.'),
                short       => 'mr',
                callback    => sub{ $obj->refresh(@_) },
                Level       => 'admin',
                DenyClass   => 'mlist',
            },
            mcovers => {
                description => gettext('Download album covers.'),
                short       => 'mc',
                callback    => sub{ $obj->getcovers(@_) },
                Level       => 'admin',
                DenyClass   => 'mlist',
            },
            mplay => {
                description => gettext("Play music file 'fid'"),
                short       => 'mp',
                callback    => sub{ $obj->play(@_) },
                DenyClass   => 'stream',
            },
            mplaylist => {
                description => gettext("Get a m3u playlist for 'fid'"),
                short       => 'm3',
                callback    => sub{ $obj->playlist(@_) },
                DenyClass   => 'stream',
            },
            mlist => {
                description => gettext("Shows music 'dir'"),
                short       => 'ml',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'mlist',
            },
            msearch => {
                description => gettext("Search music 'txt'"),
                short       => 'mf',
                callback    => sub{ $obj->search(@_) },
                DenyClass   => 'mlist',
            },
            mcoverimage => {
                description => gettext('Show album covers.'),
                short       => 'mi',
                callback    => sub{ $obj->coverimage(@_) },
                DenyClass   => 'mlist',
            },
            mgetfile => {
                description => gettext("Get music file 'fid'"),
                short       => 'mg',
                callback    => sub{ $obj->getfile(@_) },
                DenyClass   => 'mlist',
            },
            msuggest => {
                hidden      => 'yes',
                callback    => sub{ $obj->suggest(@_) },
                DenyClass   => 'mlist',
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

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize modul!');

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error('No object defined!');

    return 1
      if($obj->{active} eq 'n');

    $obj->{Amazon} = Net::Amazon->new(
        token       => '1CCSPM94SQW5RNWY6682',
    );

    $obj->{mdbh} = $obj->ConnectToMuggleDB($obj->{muggle});

    #create an instance to find all files below /usr/local/mp3
    $obj->{ICE} = MP3::Icecast->new();
#   $obj->{ICE}->recursive(1);

#   Use "file::find" & "add_file" instead of use "add_directory" 
#   avoid dead of modul via link-loops like cd /mp3; ln -s foo ../mp3
#   $obj->{ICE}->add_directory($obj->{path});
    find( {
      wanted => sub{
        if(-r $File::Find::name) {
          $obj->{ICE}->add_file($File::Find::name)
            if($File::Find::name =~ /\.mp3$/sig);  # Lookup for *.mp3
          } else {
            lg "Permissions deny, couldn't read : $File::Find::name";
          }
        },
        follow => 1,
        follow_skip => 2,
        },
      $obj->{path}
    );

    $obj->{SOCK} = IO::Socket::INET->new(
        LocalPort => $obj->{port}, #standard Icecast port
        LocalAddr => $obj->{Interface},
        Listen    => $obj->{clients},
        Proto     => 'tcp',
        Reuse     => 1,
        Timeout   => 3600
    );

    my $channels;

    Event->io(
        fd => $obj->{SOCK},
        prio => -1,  # -1 very hard ... 6 very low
        cb => sub {
            # accept client
            my $client = $obj->{SOCK}->accept;
            panic "Couldn't connect to new icecast client." and return unless $client;
            $client->autoflush;

            # make "channel" number
            my $channel=++$channels;

            # install a communicator
            Event->io(
                fd => $client,
                prio => -1,  # -1 very hard ... 6 very low
                poll => 'r',
                cb => sub {
                    my $watcher = shift;
                    # report
                    lg(sprintf("Talking on icecast channel %d", $channel));

                    # read new line and report it
                    my $handle=$watcher->w->fd;
                    my $data = $obj->parseRequest($handle);
                    my $files = $obj->handleInput($data);
                    unless(ref $files eq 'ARRAY') {
                        $watcher->w->cancel;
                        $client->close();
                        undef $watcher;
                        return 1;
                    }

                    $obj->stream($files, $client);

                    $watcher->w->cancel;
                    undef $watcher;
                    $client->close;
                },
            );

            # report
            lg(sprintf("Open new icecast channel %d", $channel));
        },
    );

    unless($obj->{mdbh}) {

        unless($obj->{dbh}) {
          panic("Session to database is'nt connected");
          return 0;
        }

        my $version = 26; # Must be increment if rows of table changed
        # this tables hasen't handmade user data,
        # therefore old table could dropped if updated rows
        if(!tableUpdated($obj->{dbh},'MUSIC',$version,1)) {
          return 0;
        }

        $obj->{dbh}->do(qq|
          CREATE TABLE IF NOT EXISTS MUSIC (
              Id int(11) unsigned auto_increment NOT NULL,
              FILE text NOT NULL,
              ARTIST varchar(128) default 'unknown',
              ALBUM varchar(128) default 'unknown',
              TITLE varchar(128) default 'unknown',
              COMMENT varchar(128),
              TRACKNUM varchar(10) default '0',
              YEAR smallint(4) unsigned,
              GENRE varchar(128),
              BITRATE smallint(4) unsigned,
              FREQUENCY varchar(4),
              SECS int (11) NOT NULL,
              PRIMARY KEY  (ID)
            ) COMMENT = '$version'
        |);

        $obj->{fields} = fields($obj->{dbh}, 'SELECT SQL_CACHE  * from MUSIC');

        # Read File to Database, if the DB empty and Musicdir exists
        $obj->refresh()
            unless($obj->{dbh}->selectrow_arrayref("SELECT SQL_CACHE  count(*) from MUSIC")->[0]);
    }

    return 1;

}

# ------------------
sub refresh {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    if( ref $console and not -d $obj->{path} ) {
        my $errmsg = sprintf(gettext("Directory of the music files '%s' not found"), $obj->{path});
        error($errmsg);
        $console->err($errmsg);
        $console->link({
            text => gettext("Back to music list"),
            url => "?cmd=mlist",
        }) if($console->typ eq 'HTML');
        return;
    }

    if($obj->{mugglei} and $obj->{mdbh}) {
        my $usr = main::getGeneralConfig->{USR};
        my $pwd = main::getGeneralConfig->{PWD};
        my $host = (split(/ /, $dbh->{'mysql_hostinfo'}))[0];
        # /usr/local/bin/mugglei -h 127.0.0.1 -c -u xpix -w xpix97 -t /NAS/Music .
        my $command = sprintf('%s -h %s -z -c -u %s -w %s -t %s . 2>&1',
            $obj->{mugglei}, lc($host), $usr, $pwd, $obj->{path});
        lg sprintf("Execute: cd '%s';%s",$obj->{path},$command);
        chdir($obj->{path});
        my @erg = (`$command`);

        if( ref $console) {
            $console->message(gettext("Reread the music files ..."));
            $console->link({
                text => gettext("Back to music list"),
                url => "?cmd=mlist",
            }) if($console->typ eq 'HTML');
        }
        undef $obj->{GENRES}; # delete genres cache

        return 1;
    }

    my $waiter;
    # Show waiter, early as is possible
    if(ref $console && $console->typ eq 'HTML') {
        $waiter = $console->wait(gettext("Get information from music files ..."), 0, 1000, 'no');
    }

    lg('Please wait! I search for new Musicfiles!');

    #create an instance to find all files below /usr/local/mp3
    $obj->{ICE} = MP3::Icecast->new();
    $obj->{ICE}->recursive(1);
    $obj->{ICE}->add_directory($obj->{path});

    $obj->{CACHE} = {};

    my $data = $dbh->selectall_hashref("SELECT SQL_CACHE  ID, FILE from MUSIC", 'FILE');
    my @files = $obj->{ICE}->files;

    lg sprintf('Found %d music files !', scalar @files);

    return unless(scalar @files);

    if( ref $console and not scalar @files ) {

        # last call of waiter
        $waiter->end() if(ref $waiter);

        $console->start() if(ref $waiter);

        $console->err(gettext("No music files found!"));
        $console->link({
            text => gettext("Back to music list"),
            url => "?cmd=mlist",
        }) if($console->typ eq 'HTML');

        return;
    }

    # Adjust waiter max value now.
    $waiter->max(scalar @files)
        if(ref $waiter);

    my $c = 0;
    my $new = 0;
    foreach my $file (@files) {
        ++$c;
        $waiter->next($c)
            if(ref $waiter);
        next if(delete $data->{$file});
        my $info = MP3::Info->new($file);
        $new++
            if($obj->insert($info));
    }

    foreach my $f (sort keys %$data) {
        unless(-e $f) {
            $dbh->do(sprintf('DELETE FROM MUSIC WHERE ID = %lu', $data->{$f}->{ID}));
        }
    }

    # last call of waiter
    $waiter->end() if(ref $waiter);

    if(ref $console) {
        $console->start()
            if(ref $waiter);
        my $msg = sprintf(gettext("%d new music files in database saved and %d non exists entries deleted!"), $new, scalar keys %$data);
        $console->message($msg);
        lg $msg;
        $console->link({
            text => gettext("Back to music list"),
            url => "?cmd=mlist",
        }) if($console->typ eq 'HTML');
    }
}

# ------------------
sub play {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return error('No data defined!');

    debug sprintf('Call play%s',
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    $console->player("?cmd=mplaylist&data=${data}&binary=1");
}

# ------------------
sub playlist {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return error('No data defined!');

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    my $host = main::getModule('STREAM')->{host} || main::getModule('STATUS')->IP;
    my $output;

    foreach my $id (split('_', $data)) {
        my $data;
        if($obj->{mdbh}) {
            $data = $dbh->selectrow_hashref("SELECT SQL_CACHE  * from tracks where id = '$id'");
        } else {
            $data = $dbh->selectrow_hashref("SELECT SQL_CACHE  * from MUSIC where ID = '$id'");
        }
        next unless($data);
  
        $output .= "#EXTM3U\r\n" unless($output);

        my $file;
        my $proxy = $obj->{proxy};
        $proxy =~ s/^\s+//;               # no leading white space
        $proxy =~ s/\s+$//;               # no trailing white space
        if(length($proxy)) {
            $file = sprintf('%s/?cmd=play&data=%s&field=id', $proxy, $id);
        } else {
            $file = sprintf('http://%s:%lu/?cmd=play&data=%s&field=%s', $host, $obj->{port}, $id, ($obj->{mdbh} ? 'id' : 'ID'));
        }
        if($obj->{mdbh}) {
            $output .= sprintf("#EXTINF:%d,%s - %s (%s)\r\n",$data->{'length'},$data->{title},$data->{artist},$data->{sourceid});
        } else {
            $output .= sprintf("#EXTINF:%d,%s - %s (%s)\r\n",$data->{SECS},$data->{TITLE},$data->{ARTIST},$data->{ALBUM});
        }
        $output .= sprintf("%s\r\n", $file);
    }

    if($output && $console->typ eq 'HTML') {
        $console->{noFooter} = 1;
        $console->{nopack} = 1;
        $console->{nocache} = 1;

        my $arg;
        $arg->{'attachment'} = "playlist.m3u";
        $arg->{'Content-Length'} = length($output);

        $console->out($output, "audio/x-mpegurl", %{$arg} );
    } else {
      $console->err(gettext("Sorry, playback is'nt supported"));
    }
}

# ------------------
sub search {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text   = shift;

    unless($text) {
      error("No text to search defined! Please use msearch 'text'");
      return $obj->list($watcher,$console);
    } else {
      return $obj->list($watcher,$console,"search:".$text);
    }
}

# ------------------
sub list {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $param  = shift;

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});
    return 0
      if(!$dbh);

    # Genres cachen
    $obj->{GENRES} = $dbh->selectall_hashref('SELECT SQL_CACHE  * from genre', 'id')
        if($obj->{mdbh} && !$obj->{GENRES});

    if($obj->{mdbh} && ! $param) {
        my $eg = $dbh->selectrow_arrayref('SELECT SQL_CACHE  title from album limit 1')
            || return $console->err($obj->{mdbh}->errstr);
        $param = sprintf('album:%s', $eg->[0]);
    } elsif(! $param) {
        my $eg = $dbh->selectrow_arrayref('SELECT SQL_CACHE  ALBUM from MUSIC limit 1')
            || return $console->err($dbh->errstr);
        $param = sprintf('album:%s', $eg->[0]);
    }

    my @field = split(':',$param);
    my $typ = $field[0];

    # Muggleübersetzer ;)
    my $translate = {
        artist  => 'artist',
        album   => 'title',
        genre   => 'genre1',
        title   => 'title',
        year   => 'year',
    };

    shift @field;
    my $text = join(':',@field);

    my $t;
    if($typ eq 'genre') {
        $t = ($obj->{mdbh} ? 'tracks.'.$translate->{$typ} : uc($typ));
        $text = $obj->{GENRES}->{$text}->{id} if($obj->{mdbh});
    } elsif($typ eq 'year') {
        $t = ($obj->{mdbh} ? 'tracks.'.$translate->{$typ} : uc($typ));
    } elsif($typ eq 'album') {
        $t = ($obj->{mdbh} ? 'album.'.$translate->{$typ} : uc($typ));
    } else {
        $t = ($obj->{mdbh} ? 'tracks.'.$translate->{$typ} : uc($typ));
    }

    my $search = '';
    my $term;
    if($typ eq 'search') {
        if($obj->{mdbh}) {
            my $query = buildsearch("album.artist,tracks.artist,album.title,tracks.title,album.covertxt",$text);
            $search = $query->{query};
            foreach(@{$query->{term}}) { push(@{$term},$_); }
            foreach(@{$query->{term}}) { push(@{$term},$_); } #double for UNION
        } else {
            my $query = buildsearch("ALBUM,ARTIST,TITLE,COMMENT",$text);
            $search = $query->{query};
            foreach(@{$query->{term}}) { push(@{$term},$_); }
        }
    } elsif($typ eq 'genre' && $obj->{mdbh}) {
        $search = sprintf("%s LIKE ?", $t);  #?%
        push(@{$term},$text.'%');
    } else {
        $search = sprintf("%s RLIKE ?", $t); #%?%
        push(@{$term},$text);
        push(@{$term},$text) if($obj->{mdbh});
    }

    my %f = (
        'Id' => gettext('Service'),
        'Artist' => gettext('Artist'),
        'Album' => gettext('Album'),
        'Title' => gettext('Title'),
        'Tracknum' => gettext('Number of track'),
        'Year' => gettext('Year'),
        'Length' => gettext('Length')
    );

    my $sql;
    if($obj->{mdbh}) {

        $sql = qq|
        SELECT SQL_CACHE 
        	tracks.id as \'$f{'Id'}\',
        	tracks.artist as \'$f{'Artist'}\',
        	album.title as \'$f{'Album'}\',
        	tracks.title as \'$f{'Title'}\',
        	tracks.tracknb as \'$f{'Tracknum'}\',
        	tracks.year as \'$f{'Year'}\',
          IF(tracks.length >= 3600,SEC_TO_TIME(tracks.length),DATE_FORMAT(FROM_UNIXTIME(tracks.length), '%i:%s')) as \'$f{'Length'}\',
          genre.genre as __GENRE,
        	album.covertxt as __COMMENT
        FROM
        	tracks, album, genre
        WHERE
            tracks.sourceid = album.cddbid and
            tracks.genre1 = genre.id and
        	  $search
        |;

        $sql .= qq|

     UNION
        SELECT SQL_CACHE 
        	tracks.id as \'$f{'Id'}\',
        	tracks.artist as \'$f{'Artist'}\',
        	album.title as \'$f{'Album'}\',
        	tracks.title as \'$f{'Title'}\',
        	tracks.tracknb as \'$f{'Tracknum'}\',
        	tracks.year as \'$f{'Year'}\',
          IF(tracks.length >= 3600,SEC_TO_TIME(tracks.length),DATE_FORMAT(FROM_UNIXTIME(tracks.length), '%i:%s')) as \'$f{'Length'}\',
          "" as __GENRE,
        	album.covertxt as __COMMENT
        FROM
        	tracks, album
        WHERE
            tracks.sourceid = album.cddbid and
            tracks.genre1 = 'NULL' and
        	  $search

        | if($typ ne 'genre');


        $sql .= qq|
        ORDER BY
                \'$f{'Album'}\',
                \'$f{'Tracknum'}\'
        |;

    } else {

        $sql = qq|
        SELECT SQL_CACHE 
        	ID as \'$f{'Id'}\',
        	ARTIST as \'$f{'Artist'}\',
        	ALBUM as \'$f{'Album'}\',
        	TITLE as \'$f{'Title'}\',
        	TRACKNUM as \'$f{'Tracknum'}\',
        	YEAR as \'$f{'Year'}\',
            IF(SECS >= 3600,SEC_TO_TIME(SECS),DATE_FORMAT(FROM_UNIXTIME(SECS), '%i:%s')) as \'$f{'Length'}\',
        	GENRE as __GENRE,
        	COMMENT as __COMMENT
        FROM
        	MUSIC
        WHERE
          1 AND
        	$search
        ORDER BY
        	FILE
        |;
    }

    my $fields = fields($dbh, $sql);

    my $sth = $dbh->prepare($sql);
    $sth->execute(@{$term})
      or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);

    my $params = {
        albums =>  ($obj->{mdbh} ? $obj->GroupArray('title', 'album', 'cddbid') : $obj->GroupArray('ALBUM')),
        artists => ($obj->{mdbh} ? $obj->GroupArray('artist', 'tracks', 'id'): $obj->GroupArray('ARTIST')),
        genres =>  $obj->GenreArray(),
        getCover => sub{ return $obj->_findcoverfromcache(@_, 'relative') },
        proxy => $obj->{proxy},
    };

    $console->table($erg, $params);
}

# ------------------
sub handleInput {
# ------------------
    my $obj     = shift || return error('No object defined!');
    my $data    = shift || return error('No request defined!');
    my $cgi = CGI->new( $data->{Query} );

    my $ucmd = $cgi->param('cmd')   || 'play';
    my $ufield = $cgi->param('field') || ($obj->{mdbh} ? 'id' : 'ID');
    my $udata = $cgi->param('data') || '*';

    my $files;
    if($ucmd eq 'play' and $ufield and my @search = split(',',$udata)) {
        $files = $obj->field2path($ufield, \@search);
    } else {
        return error "I don't understand this command '$ucmd'";
    }
    return $files;
}

# ------------------
sub field2path {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return error('No field defined!');
    my $data = shift || return error('No data defined!');
    my $pathfield;
    my $sql;

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    return 0
      if(!$dbh);

    map {$_ = $dbh->quote($_)} @$data;

    if($obj->{mdbh}) {
      $pathfield = 'mp3file';
      $sql = sprintf "SELECT SQL_CACHE  %s, %s from tracks", $pathfield, $field;
    } else {
      $pathfield = 'FILE';
      $sql = sprintf "SELECT SQL_CACHE  %s, %s from MUSIC", $pathfield, $field;
    }
    $sql .= sprintf " where %s in (%s)", $field, join(',', @$data)
        if($data->[0] ne '*');

    my $ret = $dbh->selectall_hashref($sql, $pathfield);
    my @files = sort keys %$ret;
    return \@files;
}

# ------------------
sub insert {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $data = shift || return 0;

    my @setdata;
    foreach my $name (keys %$data) {
        next unless(grep($name eq $_, @{$obj->{fields}}));
        push(@setdata, sprintf("%s=%s", $name, $obj->{dbh}->quote($data->{$name})));
    }

    # MD5(File) as ID
    my $sql = sprintf('INSERT INTO MUSIC SET %s', join(', ', @setdata));
    # dumper($sql);
    $obj->{dbh}->do( $sql );
    return 1;
}

# ------------------
sub stream {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $files = shift || return error('No file defined!');
    my $client = shift || return error('No client defined!');

    my %seen = ();
    my @uniqu = grep { ! $seen{$_} ++ } @$files;

    defined(my $child = fork()) or die "Couldn't fork: $!";
    if($child == 0) {
        $obj->{SOCK}->close;
        $obj->{dbh}->{InactiveDestroy} = 1;

        foreach my $file (@uniqu) {

            $file = $obj->{path} . "/" . $file
                if($obj->{mdbh});

            debug sprintf('Stream file "%s"',$file);
            my $erg = $obj->{ICE}->stream($file,0,$client)
                || last;
        }
        exit 0;
    }
}

# ------------------
sub parseRequest {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $hdl = shift || return error('No request defined!');

    my ($Req, $size) = getFromSocket($hdl);

	if(ref $Req eq 'ARRAY' and $Req->[0] =~ /^GET (\/[\w\.\/-\:]*)([\?[\w=&\.\+\%-\:\!]*]*)[\#\d ]+HTTP\/1.\d$/) {
        my $data = {};
		($data->{Request}, $data->{Query}) = ($1, $2 ? substr($2, 1, length($2)) : undef);

    	# parse header
    	foreach my $line (@$Req) {
    		if($line =~ /Referer: (.*)/) {
    			$data->{Referer} = $1;
    		}
    		if($line =~ /Host: (.*)/) {
    			$data->{HOST} = $1;
    		}
    		if($line =~ /Authorization: basic (.*)/i) {
    			($data->{username}, $data->{password}) = split(":", MIME::Base64::decode_base64($1), 2);
    		}
    		if($line =~ /User-Agent: (.*)/i) {
    			$data->{http_useragent} = $1;
    		}
    	}

    # Log like Apache Format ip, resolved hostname, user, method request, status, bytes, referer, useragent
    lg sprintf('%s - %s "%s %s%s" %s %s "%s" "%s"',
          getip($hdl),
          $data->{username} ? $data->{username} : "-",
          "GET", #$data->{Method},
          $data->{Request} ? $data->{Request} : "",
          $data->{Query} ? "?" . $data->{Query} : "",
          "-", #$console->{'header'},
          "-", #$console->{'sendbytes'},
          $data->{Referer} ? $data->{Referer} : "-",
          "-" #$data->{http_useragent} ? $data->{http_useragent} : ""
        );

    return $data;
	} else {
    error sprintf(" Unknown Request : %s", join("\n", @$Req));
    return undef;
	}
}

# ------------------
sub GroupArray {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $table = shift;
    my $idfield = shift;
    my $search = shift;
    my $limitquery = shift;

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    my $where = '';
    $where = sprintf("WHERE %s LIKE '%%%%%s%%%%'",$field, $search)
        if($search);
    my $limit = '';
    $limit = sprintf("LIMIT %s",$limitquery)
        if($limitquery && $limitquery > 0);

    my $sql;
    if($obj->{mdbh}) {
        $sql = sprintf('SELECT SQL_CACHE  %s, %s from %s %s group by %s order by %s %s', $field, $idfield, $table, $where, $field, $field, $limit);
    } else {
        $sql = sprintf('SELECT SQL_CACHE  %s, ID from MUSIC %s group by %s order by %s %s %s ', $field, $where, $field, $field, $limit);
    }
    my $erg = $dbh->selectall_arrayref($sql);

    return $erg;
}

# ------------------
sub GenreArray {
# ------------------
    my $obj = shift || return error('No object defined!');

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    my $sql;
    if($obj->{mdbh}) {
        $sql = "SELECT SQL_CACHE  genre, genre.id as id from genre,tracks where genre.id = tracks.genre1 group by id order by id";
    } else {
        my $field = 'genre';
        $sql = sprintf('SELECT SQL_CACHE  %s, %s from MUSIC group by %s order by %s', $field, $field, $field, $field);
    }
    my $erg = $dbh->selectall_arrayref($sql);

    return $erg;
}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift || 0;

    return
      if($obj->{active} eq 'n');

    my $report = {};
    if($obj->{mdbh}) {
        $report->{FILE} = $obj->{mdbh}->selectrow_arrayref('SELECT SQL_CACHE  count(*) from tracks')->[0];
        $report->{ALBUM} = $obj->{mdbh}->selectrow_arrayref('SELECT SQL_CACHE  count(*) from album')->[0];
        my $d = $obj->{mdbh}->selectall_arrayref('SELECT SQL_CACHE  artist from tracks group by artist');
        $report->{ARTIST} = scalar @$d;
        $d = $obj->{mdbh}->selectall_arrayref('SELECT SQL_CACHE  genre1 from tracks group by genre1');
        $report->{GENRE} = scalar @$d;
    } else {
        foreach my $field (qw/FILE ALBUM ARTIST GENRE/) {
            my $data = $obj->GroupArray($field);
            $report->{$field} = scalar @$data;
        }
    }


    return {
        message => sprintf(gettext('Music database contains %d entries with %d albums from %d artists in %d genres'),
            $report->{FILE}, $report->{ALBUM},$report->{ARTIST}, $report->{GENRE}),
    };
}

# ------------------
sub getcovers {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $force = shift;

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    return error('No valid Amazon token exists. Please sign up at http://amazon.com/soap!')
        unless($obj->{Amazon});

    debug sprintf('Call getcovers%s',
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    my $waiter = $console->wait(gettext("Please wait, search for new covers ..."),0,1000,'no')
        if(ref $console);

    unless(-d $obj->{coverimages}) {
        mkpath($obj->{coverimages}) or error "Couldn't mkpath $obj->{coverimages} : $!";
        lg sprintf('mkdir path "%s"',
                $obj->{coverimages}
            );
    }

    my $rob = main::getModule('ROBOT')
        or return error('No ROBOT Module installed!');

    $rob->saveRobot('coverimage', sub{
        my $artist = shift || return 0, "Missing artist";
        my $album = shift || return 0, "Missing album";
        my $year = shift || 0;
        my $target = shift || return 0, "Missing target";
        my $current = shift || 0;

        my $msg = sprintf(gettext("Lookup for cover from '%s-%s'"), $artist,$album);
        lg $msg;
        # Anzeige der ProcessBar
        $waiter->next($current,undef, $msg) if(ref $waiter);

        my $req = Net::Amazon::Request::Artist->new(
            artist  => $artist,
        );
        my $resp = $obj->{Amazon}->request($req);

        $album =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
        $album =~ s/([\/])/\./g; # Replace splash

        foreach my $item ($resp->properties) {

            if($item->album() =~ /$album/i or
                ($year and $item->year() and $item->year() == $year)) {
                    my $image = $item->ImageUrlMedium()
                              or $item->ImageUrlLarge()
                              or $item->ImageUrlSmall();
                    lg sprintf("Try to get cover %s.", $image);
                    getstore($image, $target) if($image);
                    last;
                }
        }

        return 1;
    });

    my $erg;
    if($obj->{mdbh}) {
        $erg = $dbh->selectall_hashref('SELECT SQL_CACHE  DISTINCT t.id as ID,t.mp3file as FILE, a.artist as ARTIST, a.title as ALBUM, t.year as YEAR from album as a, tracks as t where a.cddbid = t.sourceid group by a.title', 'ID');
    } else {
        $erg = $dbh->selectall_hashref('SELECT SQL_CACHE  DISTINCT Id as ID, FILE, ARTIST, ALBUM, YEAR from MUSIC group by ALBUM', 'ID');
    }

    my $current = 0;
    foreach my $id (sort keys %$erg) {
        my $e = $erg->{$id};

        my $file = sprintf('%s/%s', $obj->{path}, $e->{FILE});
        my $target = $obj->_findcover($file,$e->{ARTIST},$e->{ALBUM});

        next if($target and -e $target and not $force);

        my $dest = $obj->_findcoverfromcache($e->{ALBUM},$e->{ARTIST});
        $rob->register('coverimage', $e->{ARTIST}, $e->{ALBUM}, $e->{YEAR}, $dest, ++$current);
    }

    # Adjust waiter max value now.
    $waiter->max($current || 1)
        if(ref $waiter);

    if(ref $waiter and $current) {
        $waiter->endcallback(
            sub{
                if(ref $console) {
                    $console->start();
                    $console->message(my $msg = gettext("New covers search was successfully!"));
                    lg sprintf($msg);

                    $console->link({
                        text => gettext("Back to music list"),
                        url => "?cmd=mlist",
                    }) if($console->typ eq 'HTML');
                    $console->footer();
                }
            }
        );
    }

    if(ref $waiter and not $current) {
        $waiter->endcallback(
            sub{
                if(ref $console) {
                    $console->start();
                    $console->message(gettext("It is not necessary to look for new covers because already all albums possess cover!"));

                    $console->link({
                        text => gettext("Back to music list"),
                        url => "?cmd=mlist",
                    }) if($console->typ eq 'HTML');
                    $console->footer();
                }
            }
        );
        lg sprintf('All covers exists!');
    }

    # Start Robots
    $rob->start( 'coverimage', $watcher, $console, sub{ $waiter->end if(ref $waiter and $current); } );

    return $erg;
}

# ------------------
sub _findcoverfromcache {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $album = shift || return error('No album defined!');
    my $artist = shift || 0;
    my $typ = shift || 'absolute';

    my $absolute;
    my $relative;

    if($artist) {
        $absolute = sprintf('%s/%s-%s.jpg', $obj->{coverimages}, $obj->unique($artist), $obj->unique($album));
        $relative = sprintf('/coverimages/%s-%s.jpg', $obj->unique($artist), $obj->unique($album));
    } else {
        $absolute = sprintf('%s/%s.jpg', $obj->{coverimages}, $obj->unique($album));
        $relative = sprintf('/coverimages/%s.jpg', $obj->unique($album));
    }
    return $absolute
        if($typ eq 'absolute');
    return $relative
        if(-r $absolute);

    lg sprintf("Don't find cover for %s - %s, as file %s",$artist,$album,$absolute);
    return undef;
}

# ------------------
sub unique {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $text = shift || return '';

    $text =~ s/[^0-9a-z]//sig;
    return $text;
}

# ------------------
sub ConnectToMuggleDB {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $dsn = shift  || return 0;

    $dsn =~ s/^\s+//;
    $dsn =~ s/\s+$//;

    #try to connect to muggle database
    if(length($dsn) and $obj->{active} eq 'y') {
        my $usr = main::getGeneralConfig->{USR};
        my $pwd = main::getGeneralConfig->{PWD};

        my $mdbh = DBI->connect(
                $dsn, $usr, $pwd,
                {   PrintError => 1,
                    AutoCommit => 1,
                }) || error($DBI::errstr);
        if($mdbh) {
            $mdbh->{InactiveDestroy} = 1;
            $mdbh->{mysql_auto_reconnect} = 1;
            debug sprintf('Connect to database: %s successful.', $dsn);
            return $mdbh;
        } else {
            debug('GiantDisc database not found! Use standard music database!');
            return 0;
        }
    } else {
        return 0;
    }
}

# ------------------
sub _findcover {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $file = shift || return error('No file defined!');
    my $artist = shift;
    my $album = shift;

    my $coverimage;
    my $directory = dirname($file);

    if($obj->{coverimages} && -d $obj->{coverimages}) {
      my $cache = $obj->_findcoverfromcache($album,$artist);
      $coverimage = $cache
        if($cache && -r $cache);
    }

    if(!$coverimage && -d $directory) {

      my @images = [];
      find(
              {
                  wanted => sub{
                      if(-r $File::Find::name) {
                          push(@images,$File::Find::name)
                              if($File::Find::name =~ /\.jpg$|\.jpeg$|\.gif$|\.png/sig);  # Lookup for images
                      } else {
                          lg "Permissions deny, couldn't read : $File::Find::name";
                      }
                  },
                  follow => 1,
                  follow_skip => 2,
              },
          $directory
      );

      #  An image in the same directory as the song, named like the song but with the
      #  song extension replaced with the image format extension
      #  e.g. test.mp3 -> test.jpg
      my $song = basename($file);
      $song =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
      $song =~ s/([\/])/\./g; # Replace splash
      $song =~ s/(.*)\.mp3$/$1./ig;
      my @f = grep { /$song/i } @images;
      $coverimage = $f[0]
        if(scalar @f > 0 && -r $f[0]);

      if(!$coverimage && $artist) {
        $artist =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
        $artist =~ s/([\/])/\./g; # Replace splash
        @f = grep { /\/$artist\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }

      if(!$coverimage && $album) {
        $album =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
        $album =~ s/([\/])/\./g; # Replace splash
        @f = grep { /\/$album\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }

      #  An image named "cover" with the image format extension in the same directory
      #  as the song (album cover).
      #  e.g. cover.gif
      if(!$coverimage) {
        @f = grep { /\/cover\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }

      #  An image named "artist" with the image format extension in the parent
      #  directory of the song (artist image).
      #  e.g. artist.png
      if(!$coverimage) {
        @f = grep { /\/artist\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }
      #  An image named "album" with the image format extension in the parent
      #  directory of the song (album image).
      #  e.g. album.png
      if(!$coverimage) {
        @f = grep { /\/album\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }

      #  An image named "background" with the image format extension in the base
      #  directory of the MP3 source.
      if(!$coverimage) {
        @f = grep { /\/background\./i } @images;
        $coverimage = $f[0]
          if(scalar @f > 0 && -r $f[0]);
      }
    }
  return $coverimage;
}

# ------------------
sub coverimage {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return error('No data defined!');

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    if($dbh) {
      my $sql;
      my @id = split('_',$data);
      
      my $coverimage;
      map {$_ = $dbh->quote($_)} @id;

      if($obj->{mdbh}) {
        $sql = sprintf qq|
                SELECT SQL_CACHE  id, mp3file as file, 
                        tracks.artist as artist, 
                        album.title as album 
                from tracks, album 
                where tracks.sourceid = album.cddbid 
                              and id in (%s)|, join(',', @id);
      } else {
        $sql = sprintf qq|
                SELECT SQL_CACHE  ID as id,
                        FILE as file, 
                        ARTIST as artist,
                        ALBUM as album 
                from MUSIC 
                where id in (%s)|, join(',', @id);
      }

      my $ret = $dbh->selectrow_hashref($sql);

      if($ret && $ret->{'id'})
      {
        my $file = sprintf('%s/%s', $obj->{path}, $ret->{'file'});

        $coverimage = $obj->_findcover($file,$ret->{'artist'},$ret->{'album'});
      }

      if($console->typ eq 'HTML') {
        if($coverimage) {
          $console->datei($coverimage);
        } else {
          my $HTTPD  = main::getModule('HTTPD');
          my $nocover = sprintf('%s/%s/images/nocover', $HTTPD->{paths}->{HTMLDIR}, $HTTPD->{HtmlRoot});
          if(-r $nocover . ".png") {
            $console->datei($nocover . ".png");
          } 
          elsif(-r $nocover . ".gif") {
            $console->datei($nocover . ".gif");
          } else {
            $nocover = sprintf('%s/default/images/nocover', $HTTPD->{paths}->{HTMLDIR});
            if(-r $nocover . ".png") {
              $console->datei($nocover . ".png");
            } else {
              $console->datei($nocover . ".gif");
            }
          }
      }
    }
    return 1;
  }
  $console->err(gettext("Sorry, images for cover is'nt supported"));
  return 0;
}

# ------------------
sub getfile {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return error('No data defined!');

    my $dbh = ($obj->{mdbh} ? $obj->{mdbh} : $obj->{dbh});

    if($dbh) {
      my $sql;
      my @id = split('_',$data);
      
      map {$_ = $dbh->quote($_)} @id;

      if($obj->{mdbh}) {
        $sql = sprintf qq|
                SELECT SQL_CACHE  id, mp3file as file from tracks
                where id in (%s)|, join(',', @id);
      } else {
        $sql = sprintf qq|
                SELECT SQL_CACHE  ID as id, FILE as file from MUSIC 
                where id in (%s)|, join(',', @id);
      }

      my $ret = $dbh->selectrow_hashref($sql);
      if($ret 
          && $ret->{'id'} 
          && $ret->{'file'}
          && $console->typ eq 'HTML') {
            $console->datei(sprintf('%s/%s', $obj->{path}, $ret->{'file'}));
            return 1;
        }
    }
    $console->err(gettext("Sorry, couldn't get file."));
    return 0;
}

# ------------------
sub suggest {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $search = shift;
    my $params  = shift;

    if(exists $params->{get}) {
        my $result;
        $result = ($obj->{mdbh} ? $obj->GroupArray('title', 'album', 'cddbid',$search, 25) : $obj->GroupArray('ALBUM',undef,undef,$search, 25))
            if($params->{get} eq 'album');

        $result = ($obj->{mdbh} ? $obj->GroupArray('artist', 'tracks', 'id',$search, 25): $obj->GroupArray('ARTIST',undef,undef,$search, 25))
            if($params->{get} eq 'artist');

        $result = ($obj->{mdbh} ? $obj->GroupArray('title', 'tracks', 'id',$search, 25): $obj->GroupArray('TITLE',undef,undef,$search, 25))
            if($params->{get} eq 'title');

        $console->table($result)
            if(ref $console && $result);
    }

}


1;
