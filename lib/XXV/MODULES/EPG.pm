package XXV::MODULES::EPG;
use strict;

use Tools;
use File::Basename;
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
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
        Status => sub{ $obj->status(@_) },
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
            },
            timeframe => {
                description => gettext("How much hours to display in schema"),
                default     => 2,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            search => {
                description => gettext('Search within EPG data'),
                short       => 's',
                callback    => sub{ $obj->search(@_) },
            },
            program => {
                description => gettext("List program for channel 'channel name'"),
                short       => 'p',
                callback    => sub{ $obj->program(@_) },
            },
            display => {
                description => gettext("Show program 'eventid'"),
                short       => 'd',
                callback    => sub{ $obj->display(@_) },
            },
            now => {
                description => gettext('Display events currently showing.'),
                short       => 'n',
                callback    => sub{ $obj->runningNow(@_) },
            },
            next => {
                description => gettext('Display events showing next.'),
                short       => 'nx',
                callback    => sub{ $obj->runningNext(@_) },
            },
            schema => {
                description => gettext('Display events in a schematic way'),
                short       => 'sch',
                callback    => sub{ $obj->schema(@_) },
            },
            erestart => {
                description => gettext('Update EPG data.'),
                short       => 'er',
                callback    => sub{
                    my $watcher = shift || return error('No watcher defined!');
                    my $console = shift || return error('No console defined!');

                    debug sprintf('Start reload EPG data%s',
                        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
                        );

                    $obj->startReadEpgData($watcher,$console);
                },
                Level       => 'admin',
            },
            erun => {
                description => gettext('Display the current program running in the VDR'),
                short       => 'en',
                callback    => sub{ $obj->NowOnChannel(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            conflict => {
                hidden      => 'yes',
                callback    => sub{ $obj->checkOnTimer(@_) },
            },
            edescription => {
                hidden      => 'yes',
                short       => 'ed',
                callback    => sub { $obj->getDescription(@_) },
            },
            esuggest => {
                hidden      => 'yes',
                callback    => sub{ $obj->suggest(@_) },
            },
        },
    };
    return $args;
}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift || 0;

    my $total = 0;
    my $newEntrys = 0;

    {
        my $sth = $obj->{dbh}->prepare("SELECT SQL_CACHE  count(*) as count from EPG");
        if(!$sth->execute())
        {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
        } else {
            my $erg = $sth->fetchrow_hashref();
            $total = $erg->{count} if($erg && $erg->{count});
        }
    }

    {
        my $sth = $obj->{dbh}->prepare("SELECT SQL_CACHE  count(*) as count from EPG where UNIX_TIMESTAMP(addtime) > ?");
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
            $total, scalar localtime($lastReportTime), $newEntrys),
    };
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
    $self->_init or return error('Problem to initialize modul!');

    return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error('No object defined!');

    unless($obj->{dbh}) {
      panic("Session to database is'nt connected");
      return 0;
    }

    my $version = 27; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows

    # Look for table or create this table
    foreach my $table (qw/EPG OLDEPG TEMPEPG/) {

      # remove old table, if updated version
      if(!tableUpdated($obj->{dbh},$table,$version,1)) {
        return 0;
      }

      $obj->{dbh}->do(qq|
          CREATE TABLE IF NOT EXISTS $table (
              eventid int unsigned NOT NULL default '0',
              title text NOT NULL default '',
              subtitle text default '',
              description text,
              channel_id varchar(100) NOT NULL default '',
              starttime datetime NOT NULL default '0000-00-00 00:00:00',
              duration int(11) NOT NULL default '0',
              tableid tinyint(4) default 0,
              image text default '',
              version tinyint(3) default 0,
              video varchar(100) default '',
              audio varchar(255) default '',
              addtime datetime NOT NULL default '0000-00-00 00:00:00',
              vpstime datetime default '0000-00-00 00:00:00',
              PRIMARY KEY (eventid),
              INDEX (starttime),
              INDEX (channel_id)
            ) COMMENT = '$version'
        |);
    }

    $obj->{after_updated} = [];

    # Repair later Data ...
    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Couldn't get modul SVDRP");
           return 0;
        }

        $obj->startReadEpgData();

        # Restart watcher every x hours
        Event->timer(
            interval => $obj->{interval},
            prio => 6,  # -1 very hard ... 6 very low
            cb => sub{
                lg sprintf('The read on epg data is restarted!');
                $obj->startReadEpgData();
            },
        );
        return 1;
    }, "EPG: Start read epg data and repair ...", 40);

    return 1;
}

# ------------------
sub startReadEpgData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    my $waiter;
    if(ref $console && $console->typ eq 'HTML') {
        $waiter = $console->wait(gettext("Read EPG data ..."),0,1000,'no');
    }

    # Read data over SVDRP
    my $vdata = $obj->{svdrp}->command('LSTE');
    map { 
      $_ =~ s/^\d{3}.//;
      $_ =~ s/[\r|\n]$//;
    } @$vdata;
    debug sprintf('The read on epg data start now!');


    # Adjust waiter max value now.
    $waiter->max(scalar @$vdata)
        if(ref $console && ref $waiter);

    $obj->moveOldEPGEntrys();

    # Read file row by row
    my $updated = $obj->compareEpgData($vdata,$watcher,$console,$waiter);

    $obj->deleteDoubleEPGEntrys();

    $obj->_updated($watcher,$console,$waiter) if($updated);

    # last call of waiter
    $waiter->end() if(ref $waiter);

    if(ref $console) {
        $console->start() if(ref $waiter);
        con_msg($console, sprintf(gettext("%d events in database updated."), $updated));

        $console->redirect({url => '?cmd=now', wait => 1})
            if($console->typ eq 'HTML');
    }
}

# Routine um Callbacks zu registrieren die nach dem Aktualisieren der EPG Daten 
# ausgeführt werden
# ------------------
sub updated {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $cb = shift || return error('No callback defined!');
    my $log = shift || 0;

    push(@{$obj->{after_updated}}, [$cb, $log]);
}

# Ausführen der Registrierten Callbacks nach dem Aktualisieren der EPG Daten
# ------------------
sub _updated {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $waiter = shift;

    foreach my $CB (@{$obj->{after_updated}}) {
        next unless(ref $CB eq 'ARRAY');
        lg $CB->[1]
            if($CB->[1]);
        &{$CB->[0]}($watcher,$console,$waiter)
            if(ref $CB->[0] eq 'CODE');
    }
}
# This Routine will compare data from epg.data
# and EPG Database row by row
# ------------------
sub compareEpgData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $vdata = shift || return error('No data defined!');
    my $watcher = shift;
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
    while($count < scalar $vdata) {
      ($vdrData,$channel,$channelname,$count) = $obj->readEpgData($vdata,$count);
      last if(not $channel);

      $waiter->next($count,undef, sprintf(gettext("Analyze channel '%s'"), $channelname))
        if(ref $waiter);

      # First - read database
      my $sql = qq|SELECT SQL_CACHE  eventid, title, subtitle, length(description) as ldescription, duration, UNIX_TIMESTAMP(starttime) as starttime, UNIX_TIMESTAMP(vpstime) as vpstime, video, audio from EPG where channel_id = ? |;
      my $sth = $obj->{dbh}->prepare($sql);
      $sth->execute($channel)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
      my $db_data = $sth->fetchall_hashref('eventid');

      lg sprintf("Compare EPG Database with data from vdr : %d / %d for channel '%s' - %s", scalar keys %$db_data,scalar keys %$vdrData, $channelname, $channel);
      # Compare this Hashes
      foreach my $eid (keys %{$vdrData}) {
        my $row = $vdrData->{$eid};

        # Exists in DB .. update
        if(exists $db_data->{$eid}) {
          # Compare fields
          foreach my $field (qw/title subtitle ldescription duration starttime vpstime video audio/) {
            next if(not exists $row->{$field} or not $row->{$field});
            if((not exists $db_data->{$eid}->{$field})
                or (not $db_data->{$eid}->{$field})
                or ($db_data->{$eid}->{$field} ne $row->{$field})) {
              $obj->replace($eid, $row);
              $updatedData++;
              last;
            }
          }

          # delete updated rows from hash
          delete $db_data->{$eid};

        } else {
          # Not exists in DB .. insert
          $obj->replace($eid, $row);
          $changedData++;
        }
      }

      # Delete unused EpgEntrys in DB 
      if(scalar keys %$db_data > 0) {
        my @todel = keys(%$db_data);
        my $sql = sprintf('DELETE FROM EPG WHERE eventid IN (%s)', join(',' => ('?') x @todel)); 
        my $sth = $obj->{dbh}->prepare($sql);
        if(!$sth->execute(@todel)) {
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
    my $obj = shift || return error('No object defined!');

    # Copy and delete old EPG Entrys
    $obj->{dbh}->do('REPLACE INTO OLDEPG SELECT * FROM EPG WHERE (UNIX_TIMESTAMP(EPG.starttime) + EPG.duration) < UNIX_TIMESTAMP()');
    $obj->{dbh}->do('DELETE FROM EPG WHERE (UNIX_TIMESTAMP(EPG.starttime) + EPG.duration) < UNIX_TIMESTAMP()');
}

# ------------------
sub deleteDoubleEPGEntrys {
# ------------------
    my $obj = shift || return error('No object defined!');

    # Delete double EPG Entrys
    my $erg = $obj->{dbh}->selectall_arrayref('SELECT SQL_CACHE  eventid FROM EPG GROUP BY starttime, channel_id having count(*) > 1');
    if(scalar @$erg > 0) {
        lg sprintf('Repair data found %d wrong events!', scalar @$erg);
        my $sth = $obj->{dbh}->prepare('DELETE FROM EPG WHERE eventid = ?');
        foreach my $row (@$erg) {
            $sth->execute($row->[0]);
        }
    }
}

# ------------------
sub replace {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $eventid = shift || return error('No eventid defined!');
    my $attr = shift || return error('No data defined!');

    my $sth = $obj->{dbh}->prepare('REPLACE INTO EPG(eventid, title, subtitle, description, channel_id, duration, tableid, image, version, video, audio, starttime, vpstime, addtime) VALUES (?,?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),NOW())');
    $sth->execute(
        $eventid,
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
    my $obj = shift || return error('No object defined!');
    my $epgid = shift || return error('No event defined!');
    my $channel = shift || return error('No channel defined!');

    # look for NID-TID-SID for unique eventids (SID 0-30000 / TID 0 - 1000 / NID 0 - 10000
    my @id = split('-', $channel);

    # Make a fix format 0xCCCCEEEE : C-Channelid (high-word), E-Eventid(low-word) => real-eventid = uniqueid & FFFF
    my $eventid = ((($id[-3] + $id[-2] + $id[-1]) & 0x3FFF) << 16) | ($epgid & 0xFFFF);

    return $eventid;
}

# ------------------
sub readEpgData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $vdata = shift || return error('No data defined!');
    my $count = shift || 0;
    my $dataHash = {};

    my $cmod = main::getModule ('CHANNELS');
    my $channels = $cmod->ChannelArray ('Id,Name');
    my $channel;
    my $channelname;
    my $event;

    for(;$count < scalar (@$vdata);$count++) {
      my $line = @{$vdata}[$count];

      # Ok, Datarow complete...
      if($line eq 'e' and $event->{eventid} and $event->{channel}) {
        if(-e sprintf('%s/%d.png', $obj->{epgimages}, $event->{eventid})) {
          my $firstimage = sprintf('%d.png',$event->{eventid});
          $event->{image} = $firstimage."\n";
          my $imgpath = sprintf('%s/%d_?.png',$obj->{epgimages},$event->{eventid});
          foreach my $img (glob($imgpath)) {
            $event->{image} .= sprintf("%s.png\n", basename($img, '.png'));
          }
        }

        $channel = $event->{channel};
        my $eventid = $obj->encodeEpgId($event->{eventid}, $channel);

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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
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
    if($search) {

    # Channelsearch
    if($params->{channel}) {
        $search->{query} .= ' AND c.POS = ?';
        push(@{$search->{term}},$params->{channel});
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
        c.Name as \'$f{'channel'}\',
        c.POS as __Pos,
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
            LIMIT 1) as __running
    from
        EPG as e,
        CHANNELS as c
    where
        e.channel_id = c.Id
        AND ( $search->{query} )
        AND ((UNIX_TIMESTAMP(e.starttime) + e.duration) > UNIX_TIMESTAMP())
    order by
        starttime
        |;
        my $fields = fields($obj->{dbh}, $sql);
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute(@{$search->{term}})
          or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
        $erg = $sth->fetchall_arrayref();
        map {
            $_->[7] = datum($_->[7],'weekday');
        } @$erg;

        unshift(@$erg, $fields);
    }
    my $modC = main::getModule('CHANNELS');
    $console->table($erg,  {
                            channels => $modC->ChannelArray('Name'),
    });
}

# ------------------
sub program {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $channel = shift || $obj->{dbh}->selectrow_arrayref("SELECT SQL_CACHE  POS from CHANNELS limit 1")->[0];

    my $mod = main::getModule('CHANNELS');

    my $cid;
    if($channel =~ /^\d+$/sig) {
        $cid = $mod->PosToChannel($channel)
            or return con_err($console, sprintf(gettext("This channel '%s' does not exist in the database!"),$channel));
    } else {
        $cid = $mod->NameToChannel($channel)
            or return con_err($console, sprintf(gettext("This channel '%s' does not exist in the database!"),$channel));
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
        LIMIT 1) as __running
from
    EPG as e, CHANNELS as c
where
    e.channel_id = c.Id
    AND ((UNIX_TIMESTAMP(e.starttime) + e.duration) > UNIX_TIMESTAMP())
    AND e.channel_id = ?
order by
    starttime
|;
    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($cid)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();
    map {
        $_->[5] = datum($_->[5],'weekday');
    } @$erg;

    unshift(@$erg, $fields);


    $console->table($erg, {
                            channels => $mod->ChannelWithGroup('Name,POS'),
                            current => $mod->ChannelToPos($cid),
                          }
                    );
}

# ------------------
sub display {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
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
    c.Name as \'$f{'Channel'}\',
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
    e.channel_id as __channel_id
from
    $table as e,CHANNELS as c
where
    e.channel_id = c.Id
    and eventid = ?
|;
    $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventid)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data   = shift;
    my $param   = shift || {};
    my $cgroups = main::getModule('CHANNELS')->ChannelGroupsArray('Name');
    my $cgrp    = $param->{cgrp} || $cgroups->[0][1]; # Erster GroupEintrag

    # Create temporary table
    $obj->{dbh}->do(qq|
CREATE TEMPORARY TABLE IF NOT EXISTS NEXTEPG (
    channel_id varchar(100) NOT NULL default '',
    nexttime datetime NOT NULL default '0000-00-00 00:00:00'
    )
|);
    # Remove old data
    $obj->{dbh}->do('delete from NEXTEPG');

    # Get channelid and starttime of next broadcasting
    my $sqltemp = qq|
INSERT INTO NEXTEPG select 
    c.Id as channel_id,
    MIN(e.starttime) as nexttime
    FROM EPG as e, CHANNELS as c
    WHERE e.channel_id = c.Id
AND e.starttime > NOW()
AND c.GRP = ?

GROUP BY c.Id
|;
    my $sthtemp = $obj->{dbh}->prepare($sqltemp);
    $sthtemp->execute($cgrp)
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
    c.Name as \'$f{'Channel'}\',
    c.POS as __POS,
    g.Name as __Channelgroup,
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
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC
FROM
    EPG as e, CHANNELS as c, NEXTEPG as n, CHANNELGROUPS as g
WHERE
    e.channel_id = c.Id
    AND n.channel_id = c.Id
    AND c.GRP = g.Id
    AND e.starttime = n.nexttime
    AND c.GRP = ?
ORDER BY
    c.POS|;
    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($cgrp)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);

    $console->table($erg,
        {
            periods => $obj->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp,
        }
    );
}

# ------------------
sub runningNow {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $zeit = shift || time;
    my $param   = shift || {};
    my $cgroups = main::getModule('CHANNELS')->ChannelGroupsArray('Name');
    my $cgrp    = $param->{cgrp} || $cgroups->[0][1]; # Erster GroupEintrag

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
    c.Name as \'$f{'Channel'}\',
    c.POS as __POS,
    g.Name as __Channelgroup,
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
    IF(e.vpstime!=0,DATE_FORMAT(e.vpstime, '%H:%i'),'') as __PDC
FROM
    EPG as e, CHANNELS as c, CHANNELGROUPS as g
WHERE
    e.channel_id = c.Id
    AND c.GRP = g.Id
    AND ? BETWEEN UNIX_TIMESTAMP(e.starttime)
    AND (UNIX_TIMESTAMP(e.starttime) + e.duration)
    AND c.GRP = ?
ORDER BY
    c.POS|;

    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($zeit, $cgrp)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);

    $console->table($erg,
        {
            zeit => $zeit,
            periods => $obj->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp,
        }
    );
}

# ------------------
sub NowOnChannel {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $channel = shift || $obj->_actualChannel || return con_err($console, gettext('No channel defined!'));
    my $zeit = time;

    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as Service,
    e.title as Title,
    e.subtitle as Subtitle,
    c.Name as Channel,
    c.POS as POS,
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
        LIMIT 1) as __running
FROM
    EPG as e, CHANNELS as c
WHERE
    e.channel_id = c.Id
    AND ? BETWEEN UNIX_TIMESTAMP(e.starttime)
    AND (UNIX_TIMESTAMP(e.starttime) + e.duration)
    AND c.POS = ?
ORDER BY
    starttime
LIMIT 1
|;
#dumper($sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($zeit, $channel)
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
    my $obj = shift  || return error('No object defined!');

    my $erg = $obj->{svdrp}->command('chan');
    my ($chanpos, $channame) = $erg->[1] =~ /^250\s+(\d+)\s+(\S+)/sig;
    return $chanpos;
}

# ------------------
sub schema {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $zeit = shift || time;
    my $param   = shift || {};


    # i.e.: 635 --> 06:35
    $zeit = fmttime($zeit)
        if(length($zeit) <= 4);

    # i.e.: 06:35 --> timeinsecs
    if($zeit =~ /^\d+:\d+$/sig) {
        $zeit   = UnixDate(ParseDate($zeit),"%s") || time;
    }

    $zeit += 86400 if($zeit < time - ($obj->{timeframe} * 3600));
    $zeit++;
    my $zeitvon = $obj->toFullHour($zeit);

    my $zeitbis = $zeitvon + ($obj->{timeframe}*3600);
    my $cgroups = main::getModule('CHANNELS')->ChannelGroupsArray('Name');
    my $cgrp    = $param->{cgrp} || $cgroups->[0][1]; # Erster GroupEintrag

    my $sql =
qq|
SELECT SQL_CACHE 
    e.eventid as Service,
    e.title as Title,
    e.subtitle as __Subtitle,
    c.Name as Channel,
    c.POS as __POS,
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
        LIMIT 1) as __running
FROM
    EPG as e, CHANNELS as c
WHERE
    e.channel_id = c.Id
    AND
    (
        ( UNIX_TIMESTAMP(e.starttime) >= ? AND UNIX_TIMESTAMP(e.starttime) <= ? )
        OR
        ( UNIX_TIMESTAMP(e.starttime) + e.duration >= ? AND UNIX_TIMESTAMP(e.starttime) + e.duration <= ? )
        OR
        ( UNIX_TIMESTAMP(e.starttime) <= ? AND UNIX_TIMESTAMP(e.starttime) + e.duration >= ? )
    )
    AND
    c.GRP = ?
ORDER BY
    c.POS,e.starttime
|;

    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($zeitvon,$zeitbis,$zeitvon,$zeitbis,$zeitvon,$zeitbis,$cgrp)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();

    my $data = {};
    foreach my $c (@$erg) {
        push(@{$data->{$c->[4]}}, $c);
    }

    $console->table($data,
        {
            zeitvon => $zeitvon,
            zeitbis => $zeitbis,
            periods => $obj->{periods},
            cgroups => $cgroups,
            channelgroup => $cgrp,
            HouresProSite => $obj->{timeframe}
        }
    );
}

# ------------------
sub checkOnTimer {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $eid = shift  || return con_err($console, gettext('No event id defined!'));
    my $tim = main::getModule('TIMERS');

    my $sql = qq|
SELECT SQL_CACHE 
    e.starttime as starttime,
    ADDDATE(e.starttime, INTERVAL e.duration SECOND) as stoptime,
    LEFT(c.Source,1) as source,
    c.TID as transponderid
FROM
    EPG as e, CHANNELS as c
WHERE
    e.eventid = ?
    and
    e.channel_id = c.Id
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eid)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $data = $sth->fetchrow_hashref();
    my $erg = $tim->checkOverlapping($data) || ['ok'];
    my $tmod = main::getModule('TIMERS');
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
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $eid = shift || 0;

    my $event = $obj->getId($eid,"description");

    $console->message($event && $event->{description} ? $event->{description} : "")
      if(ref $console);
}

# ------------------
sub toFullHour {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $zeit = shift || return error ('No time to convert defined!');

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                             localtime($zeit);
    my $retzeit = timelocal(0, 0, $hour, $mday, $mon, $year);
    return $retzeit;
}


# ------------------
sub getId {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $id = shift || return error('No id defined!');
    my $fields = shift || '*';

    foreach my $table (qw/EPG OLDEPG/) {
    # EPG
        my $sql = sprintf('SELECT SQL_CACHE  %s from %s WHERE eventid = ?',$fields, $table); 
        my $sth = $obj->{dbh}->prepare($sql);
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
    my $obj = shift  || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $search = shift;
    my $params  = shift;
  
    if($search) {
        my $ch = '';
        if($params->{channel}) {
            $ch = " AND c.POS = ? ";
        }

        my $sql = qq|
    SELECT SQL_CACHE 
        e.title as title
    FROM
        EPG as e,
        CHANNELS as c
    WHERE
        channel_id = c.Id
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
        channel_id = c.Id
    	AND ( e.subtitle LIKE ? )
        $ch
    GROUP BY
        title
ORDER BY
    title
LIMIT 25
        |;
        my $sth = $obj->{dbh}->prepare($sql);
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

1;
