package XXV::MODULES::EPG;
use strict;

use Tools;
use File::Basename;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'EPG',
        Prereq => {
            'Date::Manip' => 'date manipulation routines',
            'Time::Local' => 'efficiently compute time from local and GMT time ',
        },
        Description => gettext('This module reads new EPG data and saves it to the database.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $self->status(@_) },
        Preferences => {
            epgimages => {
                description => gettext('Location of additional EPG images.'),
                default     => '/var/cache/vdr/epgimages',
                type        => 'dir',
            },
            interval => {
                description => gettext('How often EPG data are to be analyzed (in seconds)'),
                default     => 60 * 60,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            periods => {
                description => gettext("Preferred program times. (eg. 12:00, 18:00)"),
                default     => '12:00,18:00,20:15,22:00',
                type        => 'string',
                required    => gettext('This is required!'),
                level       => 'guest'
            },
            timeframe => {
                description => gettext("How much hours to display in schema"),
                default     => 2,
                type        => 'integer',
                required    => gettext('This is required!'),
                level       => 'guest'
            },
        },
        Commands => {
            search => {
                description => gettext('Search within EPG data'),
                short       => 's',
                callback    => sub{ $self->search(@_) },
            },
            program => {
                description => gettext("List program for channel 'channel name'"),
                short       => 'p',
                callback    => sub{ $self->program(@_) },
            },
            display => {
                description => gettext("Show program 'eventid'"),
                short       => 'd',
                callback    => sub{ $self->display(@_) },
            },
            now => {
                description => gettext('Display events currently showing.'),
                short       => 'n',
                callback    => sub{ $self->runningNow(@_) },
            },
            next => {
                description => gettext('Display events showing next.'),
                short       => 'nx',
                callback    => sub{ $self->runningNext(@_) },
            },
            schema => {
                description => gettext('Display events in a schematic way'),
                short       => 'sch',
                callback    => sub{ $self->schema(@_) },
            },
            erestart => {
                description => gettext('Update EPG data.'),
                short       => 'er',
                callback    => sub{
                    my $console = shift || return error('No console defined!');

                    debug sprintf('Start reload EPG data%s',
                        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
                        );

                    $self->startReadEpgData($console);
                },
                Level       => 'admin',
            },
            erun => {
                description => gettext('Display the current program running in the VDR'),
                short       => 'en',
                callback    => sub{ $self->NowOnChannel(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            conflict => {
                hidden      => 'yes',
                callback    => sub{ $self->checkOnTimer(@_) },
            },
            edescription => {
                hidden      => 'yes',
                short       => 'ed',
                callback    => sub { $self->getDescription(@_) },
            },
            esuggest => {
                hidden      => 'yes',
                callback    => sub{ $self->suggest(@_) },
            },
            eimage => {
                hidden      => 'yes',
                short       => 'ei',
                callback    => sub{ $self->image(@_) },
                binary      => 'cache'
            }
        },
    };
    return $args;
}

# ------------------
sub status {
# ------------------
    my $self = shift || return error('No object defined!');
    my $lastReportTime = shift || 0;

    my $total = 0;
    my $newEntrys = 0;

    {
        my $sth = $self->{dbh}->prepare("SELECT SQL_CACHE count(*) as count from EPG");
        if(!$sth->execute())
        {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
        } else {
            my $erg = $sth->fetchrow_hashref();
            $total = $erg->{count} if($erg && $erg->{count});
        }
    }

    {
        my $sth = $self->{dbh}->prepare("SELECT SQL_CACHE count(*) as count from EPG where UNIX_TIMESTAMP(addtime) > ?");
        if(!$sth->execute($lastReportTime))
        {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
        } else {
            my $erg = $sth->fetchrow_hashref();
            $newEntrys = $erg->{count} if($erg && $erg->{count});
        }
    }

    return {
        message => sprintf(gettext('EPG table contains %d entries and since the last login on %s %d new entries.'),
            $total, datum($lastReportTime), $newEntrys),
        complete => $total
    };
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

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # The Initprocess
    $self->_init or return error('Problem to initialize modul!');

    return $self;
}

# ------------------
sub _init {
# ------------------
    my $self = shift || return error('No object defined!');

    unless($self->{dbh}) {
      panic("Session to database is'nt connected");
      return 0;
    }

    my $version = 32; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows

    # Look for table or create this table
    foreach my $table (qw/EPG OLDEPG TEMPEPG/) {

      # remove old table, if updated version
      if(!tableUpdated($self->{dbh},$table,$version,1)) {
        return 0;
      }

      $self->{dbh}->do(qq|
          CREATE TABLE IF NOT EXISTS $table (
              eventid int unsigned NOT NULL default '0',
              vid int unsigned NOT NULL,
              title text NOT NULL default '',
              subtitle text default '',
              description text,
              channel_id varchar(32) NOT NULL default '',
              starttime datetime NOT NULL default '0000-00-00 00:00:00',
              duration int NOT NULL default '0',
              tableid tinyint(4) default 0,
              image text default '',
              version tinyint default 0,
              video varchar(32) default '',
              audio varchar(128) default '',
              addtime datetime NOT NULL default '0000-00-00 00:00:00',
              vpstime datetime default '0000-00-00 00:00:00',
              PRIMARY KEY (vid,eventid),
              INDEX (starttime),
              INDEX (channel_id)
            ) COMMENT = '$version'
        |);
    }

    $self->{before_updated} = [];
    $self->{after_updated} = [];

    # Repair later Data ...
    main::after(sub{
        $self->{svdrp} = main::getModule('SVDRP');
        unless($self->{svdrp}) {
           panic ("Couldn't get modul SVDRP");
           return 0;
        }

        $self->startReadEpgData();

        # Restart interval every x hours
        Event->timer(
            interval => $self->{interval},
            prio => 6,  # -1 very hard ... 6 very low
            cb => sub{
                lg sprintf('The read on epg data is restarted!');
                $self->startReadEpgData();
            },
        );
        return 1;
    }, "EPG: Start read epg data and repair ...", 40);

    return 1;
}

# ------------------
sub startReadEpgData {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift;
    my $config = shift;

    debug sprintf('The read on epg data start now!');

    my $waiter;
    if(ref $console && $console->typ eq 'HTML') {
        $waiter = $console->wait(gettext("Read EPG data ..."),0,1000,'no');
    }
    my $updated = 0;
    $self->_before_updated($console,$waiter);
  
    $self->moveOldEPGEntrys();

    # Read data over SVDRP
    my $hostlist = $self->{svdrp}->list_hosts();
    # read from svdrp
    foreach my $vid (@$hostlist) {
      my ($vdata,$error) = $self->{svdrp}->command('LSTE',$vid);
      unless($error) {
        map { 
          $_ =~ s/^\d{3}.//;
        # $_ =~ s/[\r|\n]$//;
        } @$vdata;


        # Adjust waiter max value now.
        $waiter->max(scalar @$vdata)
            if(ref $console && ref $waiter);

        # Read file row by row
        $updated |= $self->compareEpgData($vdata,$vid,$console,$waiter);
      }
    }
    $self->deleteDoubleEPGEntrys();

    $self->_updated($console,$waiter) if($updated);

    # last call of waiter
    $waiter->end() if(ref $waiter);

    if(ref $console) {
        $console->start() if(ref $waiter);
        con_msg($console, sprintf(gettext("%d events in database updated."), $updated));

        $console->redirect({url => '?cmd=now', wait => 1})
            if($console->typ eq 'HTML');
    }
}

# Routine um Callbacks zu registrieren die vor dem Aktualisieren der EPG Daten 
# ausgeführt werden
# ------------------
sub before_updated {
# ------------------
    my $self = shift || return error('No object defined!');
    my $cb = shift || return error('No callback defined!');
    my $log = shift || 0;

    push(@{$self->{before_updated}}, [$cb, $log]);
}

# Ausführen der Registrierten Callbacks vor dem Aktualisieren der EPG Daten
# ------------------
sub _before_updated {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift;
    my $waiter = shift;

    foreach my $CB (@{$self->{before_updated}}) {
        next unless(ref $CB eq 'ARRAY');
        lg $CB->[1]
            if($CB->[1]);
        &{$CB->[0]}($console,$waiter)
            if(ref $CB->[0] eq 'CODE');
    }
}

# Routine um Callbacks zu registrieren die nach dem Aktualisieren der EPG Daten 
# ausgeführt werden
# ------------------
sub updated {
# ------------------
    my $self = shift || return error('No object defined!');
    my $cb = shift || return error('No callback defined!');
    my $log = shift || 0;

    push(@{$self->{after_updated}}, [$cb, $log]);
}

# Ausführen der Registrierten Callbacks nach dem Aktualisieren der EPG Daten
# ------------------
sub _updated {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift;
    my $waiter = shift;

    foreach my $CB (@{$self->{after_updated}}) {
        next unless(ref $CB eq 'ARRAY');
        lg $CB->[1]
            if($CB->[1]);
        &{$CB->[0]}($console,$waiter)
            if(ref $CB->[0] eq 'CODE');
    }
}
# This Routine will compare data from epg.data
# and EPG Database row by row
# ------------------
sub compareEpgData {
# ------------------
    my $self = shift || return error('No object defined!');
    my $vdata = shift || return error('No data defined!');
    my $vid = shift;
    my $console = shift;
    my $waiter = shift;

    my $changedData = 0;
    my $updatedData = 0;
    my $deleteData = 0;

    # Second - read data
    my $count = 0;

    my $vdrData;
    my $channel;
    my $channelname;
    my $hostname = $self->{svdrp}->hostname($vid);

    while($count < scalar $vdata) {
      ($vdrData,$channel,$channelname,$count) = $self->readEpgData($vid,$vdata,$count);
      last if(not $channel);

      $waiter->next($count,undef, sprintf(gettext("Analyze channel '%s'"), $channelname))
        if(ref $waiter);

      # First - read database
      my $sql = qq|SELECT SQL_CACHE eventid, title, subtitle, length(description) as ldescription, duration, UNIX_TIMESTAMP(starttime) as starttime, UNIX_TIMESTAMP(vpstime) as vpstime, video, audio, image from EPG where vid = ? and channel_id = ? |;
      my $sth = $self->{dbh}->prepare($sql);
      $sth->execute($vid, $channel)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      my $db_data = $sth->fetchall_hashref('eventid');

      lg sprintf("Compare EPG Database with data from %s : %d / %d for channel '%s' - %s", $hostname, scalar keys %$db_data,scalar keys %$vdrData, $channelname, $channel);
      # Compare this Hashes
      foreach my $eid (keys %{$vdrData}) {
        my $row = $vdrData->{$eid};

        # Exists in DB .. update
        if(exists $db_data->{$eid}) {
          # Compare fields
          foreach my $field (qw/title subtitle ldescription duration starttime vpstime video audio image/) {
            next if(not exists $row->{$field} or not $row->{$field});
            if((not exists $db_data->{$eid}->{$field})
                or (not $db_data->{$eid}->{$field})
                or ($db_data->{$eid}->{$field} ne $row->{$field})) {
              $self->replace($eid, $vid, $row);
              $updatedData++;
              last;
            }
          }

          # delete updated rows from hash
          delete $db_data->{$eid};

        } else {
          # Not exists in DB .. insert
          $self->replace($eid, $vid, $row);
          $changedData++;
        }
      }

      # Delete unused EpgEntrys in DB 
      if(scalar keys %$db_data > 0) {
        my @todel = keys(%$db_data);
        my $sql = sprintf('DELETE FROM EPG WHERE vid = ? and eventid IN (%s)', join(',' => ('?') x @todel)); 
        my $sth = $self->{dbh}->prepare($sql);
        if(!$sth->execute($vid, @todel)) {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
        }
        $deleteData += scalar @todel;
      }
    } 
    debug sprintf('Finish .. %d events created, %d events replaced, %d events deleted', $changedData, $updatedData, $deleteData);

    return ($changedData + $updatedData + $deleteData);
}

# ------------------
sub moveOldEPGEntrys {
# ------------------
    my $self = shift || return error('No object defined!');

    # Copy and delete old EPG Entrys
    $self->{dbh}->do('REPLACE INTO OLDEPG SELECT * FROM EPG WHERE (UNIX_TIMESTAMP(EPG.starttime) + EPG.duration) < UNIX_TIMESTAMP()');
    $self->{dbh}->do('DELETE FROM EPG WHERE (UNIX_TIMESTAMP(EPG.starttime) + EPG.duration) < UNIX_TIMESTAMP()');
}

# ------------------
sub deleteDoubleEPGEntrys {
# ------------------
    my $self = shift || return error('No object defined!');

    # Delete double EPG Entrys
    my $erg = $self->{dbh}->selectall_arrayref('SELECT SQL_CACHE eventid FROM EPG GROUP BY starttime, vid, channel_id having count(*) > 1');
    if(scalar @$erg > 0) {
        lg sprintf('Repair data found %d wrong events!', scalar @$erg);
        my $sth = $self->{dbh}->prepare('DELETE FROM EPG WHERE eventid = ?');
        foreach my $row (@$erg) {
            $sth->execute($row->[0]);
        }
    }
}

# ------------------
sub replace {
# ------------------
    my $self = shift || return error('No object defined!');
    my $eventid = shift || return error('No eventid defined!');
    my $vid = shift || return error('No vid defined!');
    my $attr = shift || return error('No data defined!');

    my $sth = $self->{dbh}->prepare('REPLACE INTO EPG(eventid, vid, title, subtitle, description, channel_id, duration, tableid, image, version, video, audio, starttime, vpstime, addtime) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),NOW())');
    $sth->execute(
        $eventid,
        $vid,
        $attr->{title},
        $attr->{subtitle},
        $attr->{description},
        $attr->{channel},
        $attr->{duration},
        $attr->{tableid},
        $attr->{image} || '',
        hex($attr->{version}),
        $attr->{video} || '1 01 deu 4:3',
        $attr->{audio} || "2 03 deu stereo",
        $attr->{starttime},
        $attr->{vpstime}
    ) if($attr->{channel});
}

# ------------------
sub encodeEpgId {
# ------------------
    my $self = shift || return error('No object defined!');
    my $vid = shift || return error('No data defined!');
    my $epgid = shift || return error('No event defined!');
    my $channel = shift || return error('No channel defined!');

    # look for NID-TID-SID for unique eventids (SID 0-30000 / TID 0 - 1000 / NID 0 - 10000
    my @id = split('-', $channel);

    # Make a fix format 0xCCCCEEEE : C-Channelid (high-word), E-Eventid(low-word) => real-eventid = uniqueid & FFFF
    my $eventid = ((($id[-3] + $id[-2] + $id[-1]) & 0x3FFF) << 16) | ($epgid & 0xFFFF);
       $eventid &= 0x6FFFFFFF; # Keep 0x70000000 .... free for recording events

    return $eventid;
}

# ------------------
sub readEpgData {
# ------------------
    my $self = shift || return error('No object defined!');
    my $vid = shift || return error('No data defined!');
    my $vdata = shift || return error('No data defined!');
    my $count = shift || 0;
    my $dataHash = {};

    my $cmod = main::getModule ('CHANNELS');
    my $channels = $cmod->ChannelArray ('id,name',sprintf(" vid = '%d'", $vid));
    my $channel;
    my $channelname;
    my $event;

    for(;$count < scalar (@$vdata);$count++) {
      my $line = @{$vdata}[$count];

      # Ok, Datarow complete...
      if($line eq 'e' and $event->{eventid} and $event->{channel}) {
        if(-e sprintf('%s/%d.png', $self->{epgimages}, $event->{eventid})) {
          my $firstimage = sprintf('%d',$event->{eventid});
          $event->{image} = $firstimage."\n";
          my $imgpath = sprintf('%s/%d_?.png',$self->{epgimages},$event->{eventid});
          foreach my $img (glob($imgpath)) {
            $event->{image} .= basename($img, '.png')."\n";;
          }
        }

        $channel = $event->{channel};
        my $eventid = $self->encodeEpgId($vid, $event->{eventid}, $channel);

        $event->{title} = gettext("No title")
          unless($event->{title});
        $event->{description} = ""
          unless($event->{description});

        %{$dataHash->{$eventid}} = %{$event};

        $event = undef;
        $event->{channel} = $channel;
        next;
      } 
      elsif($line eq 'c') {
        # Finish this channel
        return ($dataHash,$channel,$channelname,$count+1)
          if(scalar keys %$dataHash);

        undef $event->{channel};
        undef $channel;
        undef $channelname;
      }

      my ($mark, $data) = $line =~ /^(\S)\s+(.+)/g;
      next unless($mark and $data);

      # Next channel 
      if($mark eq 'C') {
        if($channel) {
          debug sprintf('Missing channel endtag c at line %d',$count);
          return ($dataHash,$channel,$channelname,$count) if(scalar keys %$dataHash);
        }
        undef $event->{channel};
        my $channel = (split(/\s+/, $data))[0];
        # import only known channels
        foreach my $ch (@{$channels}) {
          if($ch->[0] eq $channel) { 
            $event->{channel} = $channel;
            $channelname = $ch->[1];
            last;
          }
        }
      } elsif($mark eq 'E') {
        ($event->{eventid}, $event->{starttime}, $event->{duration}, $event->{tableid}, $event->{version}) = split(/\s+/, $data);
      } elsif($mark eq 'T') {
        $event->{title} = $data;
      } elsif($mark eq 'S') {
        $event->{subtitle} = $data;
      } elsif($mark eq 'D') {
        $event->{description} = $data;
        $event->{description} =~ s/\|/\r\n/g;            # pipe used from vdr as linebreak
        $event->{description} =~ s/^\s+//;               # no leading white space
        $event->{description} =~ s/\s+$//;               # no trailing white space
        $event->{ldescription} = length($event->{description});
      } elsif($mark eq 'X') {
        my @d = split(/\s+/, $data);
        if($d[0] eq '1') {
          $event->{video} .= $data;
        } else {
          $event->{audio} .= $data."\n";
        }
      } elsif($mark eq 'V') {
        $event->{vpstime} = $data;
      }
    }
    return ($dataHash,$channel,$channelname,$count);
}

# ------------------
sub search {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $data = shift;
    my $params = shift;

    # Textsearch
    my $search;
    if($data) {
        if($params->{Where} && $params->{Where} eq 'title') {
            $search = buildsearch("e.title",$data);
        } elsif($params->{Where} && $params->{Where} eq 'titlesubtitle') {
            $search = buildsearch("e.title,e.subtitle",$data);
        } else {
            $search = buildsearch("e.title,e.subtitle,e.description",$data);
        }
    }

    my $erg = [];
    my $rows = 0;
    my $cmod = main::getModule('CHANNELS');

    if($search) {

      # Channelsearch
      if($params->{channel}) {
          $search->{query} .= ' AND c.hash = ?';
          push(@{$search->{term}}, $cmod->ToHash($params->{channel}));
      }

      # Videoformat search
      if($params->{Videoformat} && $params->{Videoformat} eq 'widescreen') {
          $search->{query} .= ' AND e.video like "%%16:9%%"';
      }

      # Audioformat search
      # XXX: Leider kann man an den Audioeintrag nicht richtig erkennnen
      # hab erst zu spät erkannt das diese Info aus dem tvm2vdr kommen ;(
  #    if($params->{Audioformat} eq 'dts') {
  #        $search->{query} .= ' AND e.audio like "%%Digital%%"';
  #    }

      # MinLength search
      if($params->{MinLength}) {
          $search->{query} .= ' AND e.duration >= ?';
          push(@{$search->{term}},($params->{MinLength}*60));
      }

      my %f = (
          'id' => gettext('Service'),
          'title' => gettext('Title'),
          'channel' => gettext('Channel'),
          'start' => gettext('Start'),
          'stop' => gettext('Stop'),
          'day' => gettext('Day')
      );

      my $sql = qq|
      SELECT SQL_CACHE 
          e.eventid as \'$f{'id'}\',
          e.title as \'$f{'title'}\',
          e.subtitle as __Subtitle,
          c.name as \'$f{'channel'}\',
          c.hash as __position,
          DATE_FORMAT(e.starttime, '%H:%i') as \'$f{'start'}\',
          DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(e.starttime) + e.duration), '%H:%i') as \'$f{'stop'}\',
          UNIX_TIMESTAMP(e.starttime) as \'$f{'day'}\',
          e.description as __description,
          IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,
          ( SELECT 
              t.id
              FROM TIMERS as t
              WHERE t.eventid = e.eventid
              LIMIT 1) as __timerid,
          ( SELECT 
              (t.flags & 1) 
              FROM TIMERS as t
              WHERE t.eventid = e.eventid
              LIMIT 1) as __timeractiv,
          ( SELECT 
              NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
              FROM TIMERS as t
              WHERE t.eventid = e.eventid
              LIMIT 1) as __running,
          e.video as __video,
          e.audio as __audio,
          ( SELECT 
              s.level
              FROM SHARE as s
              WHERE s.eventid = e.eventid
              LIMIT 1) as __level
      from
          EPG as e,
          CHANNELS as c
      where
          e.channel_id = c.id
          AND e.vid = c.vid
          AND ( $search->{query} )
          AND ((UNIX_TIMESTAMP(e.starttime) + e.duration) > UNIX_TIMESTAMP())
      group by
          c.id, e.eventid
      order by
          starttime
          |;

      my $sth;
      my $limit = $console->{cgi} && $console->{cgi}->param('limit') ? CORE::int($console->{cgi}->param('limit')) : 0;
      if($limit > 0) {
        # Query total count of rows
        my $rsth = $self->{dbh}->prepare($sql);
           $rsth->execute(@{$search->{term}})
            or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
        $rows = $rsth->rows;
        if($rows <= $limit) {
          $sth = $rsth;
        } else {
          # Add limit query
          if($console->{cgi}->param('start')) {
            $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
            $sql .= "," . $limit;
          } else {
            $sql .= " LIMIT " . $limit;
          }
        }
      }

      unless($sth) {
        $sth = $self->{dbh}->prepare($sql);
        $sth->execute(@{$search->{term}})
          or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $rows = $sth->rows unless($rows);
      }

      my $fields = $sth->{'NAME'};
      $erg = $sth->fetchall_arrayref();

      unless($console->typ eq 'AJAX') {
        map {
            $_->[7] = datum($_->[7],'weekday');
        } @$erg;

        unshift(@$erg, $fields);
      }
    }
    my $info = {
      rows => $rows
    };
    if($console->typ eq 'HTML') {
      $info->{channels} = $cmod->ChannelWithGroup('c.name,c.hash');
    }
    $console->table($erg, $info );
}

# ------------------
sub program {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $cid = shift;
    unless($cid) {
      my $c = $self->{dbh}->selectrow_arrayref("SELECT SQL_CACHE hash from CHANNELS order by vid, pos limit 1");
      return $console->err(gettext("No channel available!"))
        unless($c && $c->[0]);
      $cid = $c->[0];
    }


    my $cmod = main::getModule('CHANNELS');

    my $search;
    if($console->{cgi}->param('filter')) {
      $search = buildsearch("e.title,e.subtitle,e.description",$console->{cgi}->param('filter'));
      $search->{query} .= ' AND ';
    }

    $search->{query} .= ' c.hash = ?';
    $cid = $cmod->ToHash($cid);
    push(@{$search->{term}},$cid);

    my %f = (
        'id' => gettext('Service'),
        'title' => gettext('Title'),
        'start' => gettext('Start'),
        'stop' => gettext('Stop'),
        'day' => gettext('Day')
    );

    my $sql = qq|
SELECT SQL_CACHE 
    e.eventid as \'$f{'id'}\',
    e.title as \'$f{'title'}\',
    e.subtitle as __Subtitle,
    DATE_FORMAT(e.starttime, '%H:%i') as \'$f{'start'}\',
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(e.starttime) + e.duration), '%H:%i') as \'$f{'stop'}\',
    UNIX_TIMESTAMP(e.starttime) as \'$f{'day'}\',
    e.description as __Description,
    e.video as __Video,
    e.audio as __Audio,
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    ( SELECT 
        s.level
        FROM SHARE as s
        WHERE s.eventid = e.eventid
        LIMIT 1) as __level
from
    EPG as e, CHANNELS as c
where
    e.channel_id = c.id
    AND e.vid = c.vid
    AND ( $search->{query} )
    AND ((UNIX_TIMESTAMP(e.starttime) + e.duration) > UNIX_TIMESTAMP())
order by
    starttime
|;

    my $rows;
    my $sth;
    my $limit = $console->{cgi} && $console->{cgi}->param('limit') ? CORE::int($console->{cgi}->param('limit')) : 0;
    if($limit > 0) {
      # Query total count of rows
      my $rsth = $self->{dbh}->prepare($sql);
         $rsth->execute(@{$search->{term}})
          or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
      $rows = $rsth->rows;
      if($rows <= $limit) {
        $sth = $rsth;
      } else {
        # Add limit query
        if($console->{cgi}->param('start')) {
          $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
          $sql .= "," . $limit;
        } else {
          $sql .= " LIMIT " . $limit;
        }
      }
    }

    unless($sth) {
      $sth = $self->{dbh}->prepare($sql);
      $sth->execute(@{$search->{term}})
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      $rows = $sth->rows unless($rows);
    }

    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();

    unless($console->typ eq 'AJAX') {
      map {
          $_->[5] = datum($_->[5],'weekday');
      } @$erg;

      unshift(@$erg, $fields);
    }

    my $info = {
      rows => $rows
    };
    if($console->typ eq 'HTML' 
        || $console->typ eq 'WML') {
      $info->{channels} = $cmod->ChannelWithGroup('c.name,c.hash');
      $info->{current} = $cid;
    }
    $console->table($erg, $info );
}

# ------------------
sub display {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $eventid = shift;

    unless($eventid) {
        con_err($console, gettext("No ID defined to display this program! Please use display 'eid'!"));
        return;
    }

    my %f = (
        'Id' => gettext('Service'),
        'Title' => gettext('Title'),
        'Subtitle' => gettext('Subtitle'),
        'Channel' => gettext('Channel'),
        'Start' => gettext('Start'),
        'Stop' => gettext('Stop'),
        'Description' => gettext('Description'),
        'Percent' => gettext('Percent')
    );

    my $fields;
    my $erg;

   foreach my $table (qw/EPG OLDEPG/) {
    my $sql = qq|
SELECT SQL_CACHE 
    e.eventid as \'$f{'Id'}\',
    e.title as \'$f{'Title'}\',
    e.subtitle as \'$f{'Subtitle'}\',
    UNIX_TIMESTAMP(e.starttime) as \'$f{'Start'}\',
    UNIX_TIMESTAMP(e.starttime) + e.duration as \'$f{'Stop'}\',
    c.name as \'$f{'Channel'}\',
    e.description as \'$f{'Description'}\',
    e.video as __Video,
    e.audio as __Audio,
    (unix_timestamp(e.starttime) + e.duration - unix_timestamp())/duration*100 as \'$f{'Percent'}\',
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    e.image as __Image,
    UNIX_TIMESTAMP(e.vpstime) as __PDC,
    e.channel_id as __channel_id,
    ( SELECT 
        s.level
        FROM SHARE as s
        WHERE s.eventid = e.eventid
        LIMIT 1) as __level
from
    $table as e,CHANNELS as c
where
    e.channel_id = c.id
    AND e.vid = c.vid
    and eventid = ?
|;
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($eventid)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    $fields = $sth->{'NAME'};
    $erg = $sth->fetchall_arrayref();

    last
      if(scalar @{$erg} != 0 );
    }

    if(scalar @{$erg} == 0 ) {
        con_err($console, sprintf(gettext("Event '%d' does not exist in the database!"),$eventid));
        return;
    }
    if($console->{TYP} ne 'HTML') {
      map {
          $_->[3] = datum($_->[3],'voll');
          $_->[4] = datum($_->[4],'time');
          $_->[14] = datum($_->[14],'time') if($_->[14]);
      } @$erg;
    }
    unshift(@$erg, $fields);
    $console->table($erg);
}

# ------------------
sub runningNext {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $data   = shift;
    my $param   = shift || {};

    # Create temporary table
    $self->{dbh}->do(qq|
CREATE TEMPORARY TABLE IF NOT EXISTS NEXTEPG (
    channel_id varchar(100) NOT NULL default '',
    nexttime datetime NOT NULL default '0000-00-00 00:00:00'
    )
|);
    # Remove old data
    $self->{dbh}->do('delete from NEXTEPG');

    # Get channelid and starttime of next broadcasting
    my $sqltemp = qq|
INSERT INTO NEXTEPG select 
    c.id as channel_id,
    MIN(e.starttime) as nexttime
    FROM EPG as e, CHANNELS as c, CHANNELGROUPS as g
    WHERE e.channel_id = c.id
    AND e.vid = c.vid
    AND c.grp = g.id
    AND c.vid = g.vid
AND e.starttime > NOW()
|;

    my $term;
    my $grpsql = '';
    my $cmod = main::getModule('CHANNELS');
    my $cgroups = $cmod->ChannelGroupsArray('name');
    my $cgrp = $param->{cgrp} || $cgroups->[0][1]; # First id of groups;

    if($cgrp && $cgrp ne 'all') {
      my $cgrps;
      # Find any groups by same group name
      foreach my $g (@$cgroups) {
        if($g->[1] == $cgrp) {
          $cgrps = $cmod->GroupsByName($g->[0]);
          last;
        }
      }
      # build query
      if($cgrps) {
        $grpsql = sprintf(" AND g.id in (%s) ",join(',' => ('?') x @$cgrps));
        foreach my $c (@$cgrps) {
          push(@{$term},$c->[0]);
        }
      } elsif($cgrp) { # group id 
        $grpsql = " AND g.id = ? ";
        push(@{$term},$cgrp);
      }
    }
    $sqltemp .= $grpsql;
    $sqltemp .= qq|
GROUP BY c.id 
ORDER BY c.vid, c.pos
|;

    my $sthtemp = $self->{dbh}->prepare($sqltemp);
    if($term) {
      if(ref $term eq 'ARRAY') {
        my $x = 1;
        foreach (@$term) {
          $sthtemp->bind_param( $x++, $_ );
        }
      } 
      else {
        $sthtemp->bind_param( 1, $term );
      }
    }
    $sthtemp->execute()
      or return con_err($console, sprintf("Couldn't execute query: %s.",$sthtemp->errstr));

    my %f = (
        'Service' => gettext('Service'),
        'Title' => gettext('Title'),
        'Channel' => gettext('Channel'),
        'Start' => gettext('Start'),
        'Stop' => gettext('Stop')
    );
    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as \'$f{'Service'}\',
    e.title as \'$f{'Title'}\',
    e.subtitle as __Subtitle,
    c.name as \'$f{'Channel'}\',
    c.hash as __position,
    g.name as __Channelgroup,
    DATE_FORMAT(e.starttime, "%H:%i") as \'$f{'Start'}\',
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) + e.duration), "%H:%i") as \'$f{'Stop'}\',
    e.description as __Description,
    999 as __Percent,
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,
    ( SELECT 
        s.level
        FROM SHARE as s
        WHERE s.eventid = e.eventid
        LIMIT 1) as __level
FROM
    EPG as e, CHANNELS as c, NEXTEPG as n, CHANNELGROUPS as g
WHERE
    e.channel_id = c.id
    AND n.channel_id = c.id
    AND c.grp = g.id
    AND c.vid = g.vid
    AND e.starttime = n.nexttime
|;


    $sql .= $grpsql;
    $sql .= qq|
GROUP BY c.id 
ORDER BY c.vid, c.pos
|;

    my $rows;
    my $sth;
    my $limit = $console->{cgi} && $console->{cgi}->param('limit') ? CORE::int($console->{cgi}->param('limit')) : 0;
    if($limit > 0) {
      # Query total count of rows
      my $rsth = $self->{dbh}->prepare($sql);
        if($term) {
          if(ref $term eq 'ARRAY') {
            my $x = 1;
            foreach (@$term) {
              $sth->bind_param( $x++, $_ );
            }
          }
          else {
            $sth->bind_param( 1, $term );
          }
        }
        $rsth->execute()
          or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
      $rows = $rsth->rows;
      if($rows <= $limit) {
        $sth = $rsth;
      } else {
        # Add limit query
        if($console->{cgi}->param('start')) {
          $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
          $sql .= "," . $limit;
        } else {
          $sql .= " LIMIT " . $limit;
        }
      }
    }

    unless($sth) {
      $sth = $self->{dbh}->prepare($sql);
      if($term) {
        if(ref $term eq 'ARRAY') {
          my $x = 1;
          foreach (@$term) {
            $sth->bind_param( $x++, $_ );
          }
        }
        else {
          $sth->bind_param( 1, $term );
        }
      }
      $sth->execute()
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      $rows = $sth->rows unless($rows);
    }


    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    unless($console->typ eq 'AJAX') {
#      map {
#        $_->[5] = datum($_->[5],'short');
#      } @$erg;
      unshift(@$erg, $fields);
    }

    $console->table($erg,
        {
            periods => $config->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp,
            rows => $rows
        }
    );
}

# ------------------
sub runningNow {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $zeit = shift || time;
    my $param   = shift || {};

    # i.e.: 635 --> 06:35
    $zeit = fmttime($zeit)
        if(length($zeit) <= 4);

    # i.e.: 06:35 --> timeinsecs
    if($zeit =~ /^\d+:\d+$/sig) {
        $zeit   = UnixDate(ParseDate($zeit),"%s") || time;
    }

    $zeit += 86400 if($zeit < time);
    $zeit++;

    my %f = (
        'Service' => gettext('Service'),
        'Title' => gettext('Title'),
        'Channel' => gettext('Channel'),
        'Start' => gettext('Start'),
        'Stop' => gettext('Stop'),
        'Percent' => gettext('Percent')
    );
    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as \'$f{'Service'}\',
    e.title as \'$f{'Title'}\',
    e.subtitle as __Subtitle,
    c.name as \'$f{'Channel'}\',
    c.hash as __position,
    g.name as __Channelgroup,
    DATE_FORMAT(e.starttime, "%H:%i") as \'$f{'Start'}\',
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) + e.duration), "%H:%i") as \'$f{'Stop'}\',
    e.description as __Description,
    (unix_timestamp(e.starttime) + e.duration - unix_timestamp())/e.duration*100 as \'$f{'Percent'}\',
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,
    ( SELECT 
      s.level
      FROM SHARE as s
      WHERE s.eventid = e.eventid
      LIMIT 1) as __level
FROM
    EPG as e, CHANNELS as c, CHANNELGROUPS as g
WHERE
    e.channel_id = c.id
    AND c.grp = g.id
    AND e.vid = c.vid
    AND c.vid = g.vid
    AND ? BETWEEN UNIX_TIMESTAMP(e.starttime)
    AND (UNIX_TIMESTAMP(e.starttime) + e.duration)
|;

    my $cmod = main::getModule('CHANNELS');
    my $cgroups = $cmod->ChannelGroupsArray('name');
    my $cgrp = $param->{cgrp} || $cgroups->[0][1]; # First id of groups;

    my $term;
    push(@{$term},$zeit);
    if($cgrp && $cgrp ne 'all') {
      my $cgrps;
      # Find any groups by same group name
      foreach my $g (@$cgroups) {
        if($g->[1] == $cgrp) {
          $cgrps = $cmod->GroupsByName($g->[0]);
          last;
        }
      }
      # build query
      if($cgrps) {
        $sql .= sprintf(" AND g.id in (%s) ",join(',' => ('?') x @$cgrps));
        foreach my $c (@$cgrps) {
          push(@{$term},$c->[0]);
        }
      } elsif($cgrp) { # group id 
        $sql .= " AND g.id = ? ";
        push(@{$term},$cgrp);
      }
    }

    $sql .= qq|
GROUP BY c.id 
ORDER BY g.pos, c.vid, c.pos
|;

    my $rows;
    my $sth;
    my $limit = $console->{cgi} && $console->{cgi}->param('limit') ? CORE::int($console->{cgi}->param('limit')) : 0;
    if($limit > 0) {
      # Query total count of rows
      my $rsth = $self->{dbh}->prepare($sql);
         $rsth->execute(@{$term})
          or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
      $rows = $rsth->rows;
      if($rows <= $limit) {
        $sth = $rsth;
      } else {
        # Add limit query
        if($console->{cgi}->param('start')) {
          $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
          $sql .= "," . $limit;
        } else {
          $sql .= " LIMIT " . $limit;
        }
      }
    }

    unless($sth) {
      $sth = $self->{dbh}->prepare($sql);
        $sth->execute(@{$term})
          or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      $rows = $sth->rows unless($rows);
    }

    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    unless($console->typ eq 'AJAX') {
#      map {
#        $_->[5] = datum($_->[5],'short');
#      } @$erg;
      unshift(@$erg, $fields);
    }

    $console->table($erg,
        {
            zeit => $zeit,
            periods => $config->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp,
            rows => $rows
        }
    );
}

# ------------------
sub NowOnChannel {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift;
    my $config = shift;
    my $channel = shift;
    my $vid = shift || $self->{svdrp}->primary_hosts();

    $channel = $self->_actualChannel($vid) unless($channel);
    return con_err($console, gettext('No channel defined!')) unless($channel);

    my $zeit = time;

    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as Service,
    e.title as Title,
    e.subtitle as Subtitle,
    c.name as Channel,
    c.pos as POS,
    e.video as __video,
    e.audio as __audio,
    DATE_FORMAT(e.starttime, "%a %d.%m") as StartDay,
    DATE_FORMAT(e.starttime, "%H:%i") as StartTime,
    (unix_timestamp(e.starttime) + e.duration - unix_timestamp())/e.duration*100 as __Percent,
    e.description as Description,
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC,        
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    ( SELECT 
        s.level
        FROM SHARE as s
        WHERE s.eventid = e.eventid
        LIMIT 1) as __level
FROM
    EPG as e, CHANNELS as c
WHERE
    e.channel_id = c.id
    AND e.vid = c.vid
    AND ? BETWEEN UNIX_TIMESTAMP(e.starttime)
    AND (UNIX_TIMESTAMP(e.starttime) + e.duration)
    AND c.vid = ?
    AND c.pos = ?
ORDER BY
    starttime
LIMIT 1
|;
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($zeit, $vid, $channel)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchrow_hashref();

    if(ref $console) {
        return $console->table($erg);
    } else {
        return $erg;
    }
}

# ------------------
sub _actualChannel {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $vid = shift;

    my ($erg,$error) = $self->{svdrp}->command('chan', $vid);
    unless($error) {
      my ($chanpos, $channame) = $erg->[1] =~ /^250\s+(\d+)\s+(\S+)/sig;
      return $chanpos;
    } else {
      return undef;
    }
}

# ------------------
sub schema {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $zeit = shift || time;
    my $param   = shift || {};

    my $term;

    # i.e.: 635 --> 06:35
    $zeit = fmttime($zeit)
        if(length($zeit) <= 4);

    # i.e.: 06:35 --> timeinsecs
    if($zeit =~ /^\d+:\d+$/sig) {
        $zeit   = UnixDate(ParseDate($zeit),"%s") || time;
    }

    $zeit += 86400 if($zeit < time - ($config->{timeframe} * 3600));
    $zeit++;

    my $zeitvon = $self->toFullHour($zeit);
    my $zeitbis = $zeitvon + ($config->{timeframe}*3600);

    push(@$term, $zeitvon);
    push(@$term, $zeitbis);
    push(@$term, $zeitvon);
    push(@$term, $zeitbis);
    push(@$term, $zeitvon);
    push(@$term, $zeitbis);

    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as Service,
    e.title as Title,
    e.subtitle as __Subtitle,
    c.name as Channel,
    c.hash as __channelid,
    DATE_FORMAT(e.starttime, "%H:%i") as Start,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) + e.duration), "%H:%i") as Stop,
    (unix_timestamp(e.starttime) + e.duration - unix_timestamp())/e.duration*100 as Percent,
    e.description as __Description,
    UNIX_TIMESTAMP(starttime) as second_start,
    UNIX_TIMESTAMP(starttime) + e.duration as second_stop,
    e.video as __video,
    e.audio as __audio,
    e.image as __image,      
    ( SELECT 
        t.id
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timerid,
    ( SELECT 
        (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __timeractiv,
    ( SELECT 
        NOW() between t.starttime and t.stoptime AND (t.flags & 1) 
        FROM TIMERS as t
        WHERE t.eventid = e.eventid
        LIMIT 1) as __running,
    c.vid as __vid,
    c.pos as __position,
    ( SELECT 
              s.level
              FROM SHARE as s
              WHERE s.eventid = e.eventid
              LIMIT 1) as __level
FROM
    EPG as e, CHANNELS as c, CHANNELGROUPS as g
WHERE
    e.channel_id = c.id
    AND c.grp = g.id
    AND
    (
        ( UNIX_TIMESTAMP(e.starttime) BETWEEN ? AND ? )
        OR
        ( UNIX_TIMESTAMP(e.starttime) + e.duration BETWEEN ? AND ? )
        OR
        ( ? BETWEEN UNIX_TIMESTAMP(e.starttime) AND (UNIX_TIMESTAMP(e.starttime) + e.duration) )
        OR
        ( ? BETWEEN UNIX_TIMESTAMP(e.starttime) AND (UNIX_TIMESTAMP(e.starttime) + e.duration) )
    )|;

    my $cmod = main::getModule('CHANNELS');
    my $cgroups = $cmod->ChannelGroupsArray('name');
    my $cgrp = $param->{cgrp} || $cgroups->[0][1]; # First id of groups;

    if($cgrp && $cgrp ne 'all') {
      my $cgrps;
      # Find any groups by same group name
      foreach my $g (@$cgroups) {
        if($g->[1] == $cgrp) {
          $cgrps = $cmod->GroupsByName($g->[0]);
          last;
        }
      }
      # build query
      if($cgrps) {
        $sql .= sprintf(" AND g.id in (%s) ",join(',' => ('?') x @$cgrps));
        foreach my $c (@$cgrps) {
          push(@{$term},$c->[0]);
        }
      } elsif($cgrp) { # group id 
        $sql .= " AND g.id = ? ";
        push(@{$term},$cgrp);
      }
    }
    $sql .= qq|
  GROUP BY c.id,e.starttime
  ORDER BY c.vid, c.pos,e.starttime
|;

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@$term)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();

    my $data = {};
    foreach my $c (@$erg) {
        push(@{$data->{($c->[17]*100000) + $c->[18]}}, $c);
    }

    $console->table($data,
        {
            zeitvon => $zeitvon,
            zeitbis => $zeitbis,
            periods => $config->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp
        }
    );
}

# ------------------
sub checkOnTimer {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $eid = shift  || return con_err($console, gettext('No event id defined!'));

    my $sql = qq|
SELECT SQL_CACHE 
    e.starttime,
    ADDDATE(e.starttime, INTERVAL e.duration SECOND) as stoptime,
    LEFT(c.Source,1) as source,
    c.TID,
    e.vid
FROM
    EPG as e, CHANNELS as c
WHERE
    e.eventid = ?
    AND e.channel_id = c.id
    AND e.vid = c.vid
|;

    my $tmod = main::getModule('TIMERS');

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($eid)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $data = $sth->fetchrow_hashref();
    my $erg = $tmod->checkOverlapping($data) || ['ok'];

    # Zeige den Title des Timers
    foreach (@$erg) { 
      $_ = $tmod->getTimerById((split(':', $_))[0])->{file}
        unless($_ eq 'ok'); 
    }

    $console->message(join(',',@$erg))
        if(ref $console);

}

# ------------------
sub getDescription {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $eid = shift || 0;

    my $event = $self->getId($eid,"description");

    $console->message($event && $event->{description} ? $event->{description} : "")
      if(ref $console);
}

# ------------------
sub toFullHour {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $zeit = shift || return error ('No time to convert defined!');

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                             localtime($zeit);
    my $retzeit = timelocal(0, 0, $hour, $mday, $mon, $year);
    return $retzeit;
}


# ------------------
sub getId {
# ------------------
    my $self = shift || return error('No object defined!');
    my $id = shift || return error('No id defined!');
    my $fields = shift || '*';

    foreach my $table (qw/EPG OLDEPG/) {
    # EPG
        my $sql = sprintf('SELECT SQL_CACHE %s from %s WHERE eventid = ?',$fields, $table); 
        my $sth = $self->{dbh}->prepare($sql);
           $sth->execute($id) 
                or return error "Couldn't execute query: $sth->errstr.";

        my $erg = $sth->fetchrow_hashref();
        return $erg
            if($erg);
    }
    lg sprintf("Event %d does not exist!", $id);
    return {};
}

# ------------------
sub suggest {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $search = shift;
    my $params  = shift;
  
    if($search) {
        my $ch = '';
        if($params->{channel}) {
            $ch = " AND c.pos = ? ";
        }

        my $sql = qq|
    SELECT SQL_CACHE
        e.title as title
    FROM
        EPG as e,
        CHANNELS as c
    WHERE
        channel_id = c.id
      AND e.vid = c.vid
      AND ( e.title LIKE ? )
        $ch
    GROUP BY
        title
UNION
    SELECT SQL_CACHE 
        e.subtitle as title
    FROM
        EPG as e,
        CHANNELS as c
    WHERE
        channel_id = c.id
      AND e.vid = c.vid
      AND ( e.subtitle LIKE ? )
        $ch
    GROUP BY
        title
ORDER BY
    title
LIMIT 25
        |;
        my $sth = $self->{dbh}->prepare($sql);
        if($params->{channel}) {
            $sth->execute('%'.$search.'%',$params->{channel},'%'.$search.'%',$params->{channel}) 
                or return error "Couldn't execute query: $sth->errstr.";
        } else {
            $sth->execute('%'.$search.'%','%'.$search.'%')
                or return error "Couldn't execute query: $sth->errstr.";
        }
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}

# ------------------
sub image {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $config = shift || return error('No config defined!');
    my $data = shift;

    return $console->err(gettext("Sorry, get image is'nt supported"))
      if ($console->{TYP} ne 'HTML');

    return $console->status404('NULL','Wrong image parameter') 
      unless($data);

    my ($eventid) = $data =~ /^([0-9_]+)$/si;

    return $console->status404('NULL','Wrong image parameter') 
      unless($eventid);
    return $console->datei(sprintf('%s/%s.png',$self->{epgimages},$eventid));
}

1;
