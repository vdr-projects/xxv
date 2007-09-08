package XXV::MODULES::RECORDS;

use strict;

use Tools;
use File::Find;
use File::Copy;
use File::Path;
use File::Basename;
use File::stat;
use Locale::gettext;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );

    my $args = {
        Name => 'RECORDS',
        Prereq => {
            'Time::Local' => 'efficiently compute time from local and GMT time ',
        },
        Description => gettext('This module managed recordings.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Status => sub{ $obj->status(@_) },
        Preferences => {
            commandfile => {
                description => gettext('Location of reccmds.conf on your system.'),
                default     => '/var/lib/vdr/reccmds.conf',
                type        => 'file',
                required    => gettext("This is required!"),
            },
            interval => {
                description => gettext('How often recordings are to be updated (in seconds)'),
                default     => 30 * 60,
                type        => 'integer',
                required    => gettext("This is required!"),
            },
            fullreading => {
                description => gettext('How often recordings are to be completely read in (in hours)'),
                default     => 24,
                type        => 'integer',
                required    => gettext("This is required!"),
            },
            videodir => {
                description => gettext('Directory, where vdr recordings are stored.'),
                default     => '/var/lib/video',
                type        => 'dir',
                required    => gettext("This is required!"),
            },
            previewbinary => {
                description => gettext('Location of used program to produce preview images on your system.'),
                default     => '/usr/bin/mplayer',
                type        => 'file',
                required    => gettext("This is required!"),
            },
            previewcommand => {
                description => gettext('Please choose the used program to produce preview images.'),
                type        => 'list',
                choices     => [
                    [gettext('Nothing'), 'Nothing'],
                    ['MPlayer1.0pre5', 'MPlayer1.0pre5'],
                    ['MPlayer1.0pre6', 'MPlayer1.0pre6'],
                    ['vdr2jpeg',       'vdr2jpeg'],
                ],
                default     => 'Nothing',
                required    => gettext("This is required!"),
            },
            previewcount => {
                description => gettext('How many preview images produce?'),
                default     => 3,
                type        => 'integer',
            },
            previewlistthumbs => {
                description => gettext('Display list records with thumbnails?'),
                default     => 'n',
                type        => 'confirm',
            },
            previewimages => {
                description => gettext('common directory for preview images'),
                default     => '/var/cache/xxv/preview',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
            vfat => {
                description => gettext('Set this if your filename encoded for vfat filesystems'),
                default     => 'y',
                type        => 'confirm',
            },
        },
        Commands => {
            rdisplay => {
                description => gettext("Display recording 'rid'"),
                short       => 'rd',
                callback    => sub{ $obj->display(@_) },
                DenyClass   => 'rlist',
            },
            rlist => {
                description => gettext('List recordings'),
                short       => 'rl',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'rlist',
            },
            rsearch => {
                description => gettext("Search recordings 'text'"),
                short       => 'rs',
                callback    => sub{ $obj->search(@_) },
                DenyClass   => 'rlist',
            },
            rupdate => {
                description => gettext('Update recordings'),
                short       => 'ru',
                callback    => sub{ $obj->refresh(@_) },
                Level       => 'user',
                DenyClass   => 'redit',
            },
            rdelete => {
                description => gettext("Delete recording 'rid'"),
                short       => 'rr',
                callback    => sub{ $obj->delete(@_) },
                Level       => 'user',
                DenyClass   => 'redit',
            },
            redit => {
                description => gettext("Edit recording 'rid'"),
                short       => 're',
                callback    => sub{ $obj->redit(@_) },
                Level       => 'user',
                DenyClass   => 'redit',
            },
            rconvert => {
                description => gettext("Convert recording 'rid'"),
                short       => 'rc',
                callback    => sub{ $obj->conv(@_) },
                Level       => 'user',
                DenyClass   => 'redit',
            },
            rplay => {
                description => gettext("Play recording 'rid' in vdr"),
                short       => 'rpv',
                callback    => sub{ $obj->play(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            rcut => {
                description => gettext("Cut recording 'rid' in vdr"),
                short       => 'rcu',
                callback    => sub{ $obj->cut(@_) },
                Level       => 'user',
                DenyClass   => 'remote',
            },
            rsuggest => {
                hidden      => 'yes',
                callback    => sub{ $obj->suggest(@_) },
                DenyClass   => 'rlist',
            },
        },
        RegEvent    => {
            'deleteRecord' => {
                Descr => gettext('Create event entries, if a record deleted.'),

                # You have this choices (harmless is default):
                # 'harmless', 'interesting', 'veryinteresting', 'important', 'veryimportant'
                Level => 'important',

                # Search for a spezial Event.
                # I.e.: Search for an LogEvent with match
                # "Sub=>text" = subroutine =~ /text/
                # "Msg=>text" = logmessage =~ /text/
                # "Mod=>text" = modname =~ /text/
                SearchForEvent => {
                    Sub => 'RECORDS',
                    Msg => 'delr',
                },
                # Search for a Match and extract the information
                # of the RecordId
                # ...
                Match => {
                    RecordId => qr/delr\s+(\d+)/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $record  = getDataById($args->{RecordId}, 'RECORDS', 'RecordId');
                            my $epg = main::getModule('EPG')->getId($record->{eventid}, 'title, subtitle, description');


                            my $title = sprintf(gettext("Record deleted: %s"), $epg->{title});
                            my $description = "";
                               $description .= sprintf(gettext("Subtitle: %s\n"),
                                    $epg->{subtitle}) if($epg->{subtitle});
                               $description .= sprintf(gettext("Description: %s\n"),
                                    $epg->{description})  if($epg->{description});

                            main::getModule('REPORT')->news($title, $description, "display", $record->{eventid}, "important");
                        }
                    |,
                ],

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

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # define framerate PAL 25, NTSC 30
    $self->{framerate} = 25;

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize module');

  return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    unless($obj->{dbh}) {
      panic("Session to database is'nt connected");
      return 0;
    }

    # remove old table, if updated rows
    tableUpdated($obj->{dbh},'RECORDS',10,1);

    # Look for table or create this table
    my $version = main::getVersion;
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS RECORDS (
          eventid bigint unsigned NOT NULL,
          RecordId int(11) unsigned not NULL,
          RecordMD5 varchar(32) NOT NULL,
          Path text NOT NULL,
          Prio tinyint NOT NULL,
          Lifetime tinyint NOT NULL,
          State tinyint NOT NULL,
          Marks text,
          Type enum('TV', 'RADIO', 'UNKNOWN') default 'TV',
          addtime timestamp,
          PRIMARY KEY  (eventid),
          UNIQUE KEY  (eventid)
        ) COMMENT = '$version'
    |);

    $obj->{JOBS} = [];
    $obj->{after_updated} = [];
    $obj->{countReading} = 0;

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Can't get modul SVDRP");
           return 0;
        }

        # Interval to read recordings and put to DB
        Event->timer(
            interval => $obj->{interval},
            prio => 6,  # -1 very hard ... 6 very low
            cb => sub{
                $obj->readData();
                $obj->{countReading} += 1;
            },
        );
        $obj->readData();
        $obj->{countReading} += 1;
        return 1;
    }, "RECORDS: Store records in database ...", 20);

    1;
}

# ------------------
sub dot1000 {
# ------------------
    my $t = reverse shift;
    $t =~ s/(\d{3})(?=\d)(?!\d*\.)/$1./g;
    return scalar reverse $t;
}

# ------------------
sub parseData {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $vdata = shift || return error('Problem to read Data!');
    my ($event, $hash, $id, $date, $hour, $minute, $state, $duration, $title, $day, $month, $year);
    my $dataHash = {};

    foreach my $record (@{$vdata}) {
      if($record =~ /\s+\d+´\s+/) { # VDR is patched with recording length patch
            # 250-1  01.11 15:14* 50´ Discovery~Die Rose von Kerrymore Spielfilm D/2000
            ($id, $date, $hour, $minute, $state, $duration, $title)
            = $record =~ /^250[\-|\s](\d+)\s+([\d|\.]+)\s+(\d+)\:(\d+)(.?)\s*(\d*).*?\s+(.+)/si;
        } else { # Vanilla VDR
            # 250-1  01.11 15:14* Discovery~Die Rose von Kerrymore Spielfilm D/2000
            ($id, $date, $hour, $minute, $state, $title)
                = $record =~ /^250[\-|\s](\d+)\s+([\d|\.]+)\s+(\d+)\:(\d+)(.?).*?\s+(.+)/si;
        }

        unless($id) {
          error sprintf("Can't parse svdrp data : '%s'",$record);
          next;
        }

        # Split date
        ($day,$month,$year) = $date =~ /^(\d+)\.(\d+)\.(\d+)$/;

        $year += 100
            if($year < 70); # Adjust year, 0-69 => 100-169 (2000-2069)
        $year += 1900
            if($year < 1900); # Adjust year, 70-99 => 1977-1999 ... 2000-2069

        $event->{id} = $id;
        $event->{state} = $state eq '*' ? 1 : 0;
        $event->{starttime} = timelocal(0,$minute,$hour,$day,$month-1, $year);
        $event->{title} = $title;

        $hash = sprintf("%s~%s",$title,$event->{starttime});
        %{$dataHash->{$hash}} = %{$event};
    }
    return ($dataHash);
}

# ------------------
sub scandirectory {# ------------------
    my $obj = shift || return error ('No Object!');

    find(
            {
                wanted => sub{
                    if(-r $File::Find::name) {
                        push(@{$obj->{FILES}},[$File::Find::name,$obj->converttitle($File::Find::name)])
                            if($File::Find::name =~ /\.rec\/\d{3}.vdr$/sig);  # Lookup for *.rec/001.vdr
                    } else {
                        lg "Permissions deny, can't read : $File::Find::name";
                    }
                },
                follow => 1,
                follow_skip => 2,
            },
        $obj->{videodir}
    );
}

# ------------------
sub readData {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $waiter = shift;
    my $forceUpdate = shift;

    # Read recording over SVDRP
    my $lstr = $obj->{svdrp}->command('lstr');
    my $vdata = [ grep(/^250/, @$lstr) ];

    unless(scalar @$vdata) {
        # Delete old Records
        $obj->{dbh}->do('DELETE FROM RECORDS');

        my $msg = gettext('No recordings available!');
        $console->err($msg)
            if(ref $console);
        return error($msg);
    }

    # Get state from used harddrive (/video)
    my $stat = $obj->{svdrp}->command('stat disk');
    my ($total, $totalUnit, $free, $freeUnit, $percent);    
    my $totalDuration = 0;

    if($stat->[1] and $stat->[1] =~ /^250/s) {
        #250 473807MB 98028MB 79%
        ($total, $totalUnit, $free, $freeUnit, $percent)
            = $stat->[1] =~ /^250[\-|\s](\d+)(\S+)\s+(\d+)(\S+)\s+(\S+)/s;

        $obj->{CapacityMessage} = sprintf(gettext("Used %s, Total %s%s, Free %s%s"),$percent, dot1000($total), $totalUnit,  dot1000($free), $freeUnit);
        $obj->{CapacityPercent} = int($percent);

    } else {
        error("Can't get disc state : ".join("\n", @$stat));
        $obj->{CapacityMessage} = gettext("Unknown disc capacity!");
        $obj->{CapacityPercent} = 0;

    }

    my @merkIds;
    my $insertedData = 0;
    my $updatedState = 0;
    my $l = 0;
    my $err = [];

    my $vdrData = $obj->parseData($vdata);

    # Adjust waiter max value now.
    $waiter->max(scalar keys %$vdrData)
        if(ref $console && ref $waiter);

    $obj->{FILES} = undef;

    my $db_data;
    if($forceUpdate || $obj->{countReading} % ( $obj->{fullreading} * 3600 / $obj->{interval} ) == 0) {
        # Once at day, make full scan
        $obj->{dbh}->do('DELETE FROM RECORDS');
    } else {
        # read database for compare with vdr data
        my $sql = qq|select r.eventid as eventid, r.RecordId as id, 
                        UNIX_TIMESTAMP(e.starttime) as starttime, 
                        e.duration as duration, r.State as state, 
                        CONCAT_WS('~',e.title,e.subtitle) as title, 
                        CONCAT_WS('~',e.title,e.subtitle,UNIX_TIMESTAMP(e.starttime)) as hash,
                        UNIX_TIMESTAMP(e.addtime) as addtime,
                        r.Path as path,
                        r.Type as type,
                        r.Marks as marks,
                        r.RecordMD5
                 from RECORDS as r,OLDEPG as e 
                 where r.eventid = e.eventid |;
       $db_data = $obj->{dbh}->selectall_hashref($sql, 'hash');

       lg sprintf( 'Compare recording database with data from vdr : %d / %d', 
                    scalar keys %$db_data,scalar keys %$vdrData );
    }

    # Compare this Hashes
    foreach my $h (keys %{$vdrData}) {
        my $event = $vdrData->{$h};

        # Exists in DB ... update
        if($db_data && exists $db_data->{$h}) {

          $waiter->next(++$l,undef, sprintf(gettext("Update recording '%s'"), 
                                            $db_data->{$h}->{title}))
              if(ref $waiter);

          # Compare fields
          foreach my $field (qw/id state/) {
            if($db_data->{$h}->{$field} != $event->{$field}) {

              $obj->_updateState($db_data->{$h}, $event);

              $updatedState++;
              last;
            }
          }

          # Update Duration and maybe preview images, if recordings added during timer run 
          if(($db_data->{$h}->{starttime} + $db_data->{$h}->{duration} + 60) > $db_data->{$h}->{addtime}) {
              my $duration = $obj->_recordinglength($db_data->{$h}->{path});
              if($duration != $db_data->{$h}->{duration}) {

                  unless($console) {
                    # set addtime only if called from EVENT::TIMER
                    # avoid generating preview image during user actions
                    # it's should speedup reading recordings
                    $db_data->{$h}->{addtime} = time;

                    # Make Preview and remove older Preview images
                    my $command = $obj->videoPreview( $db_data->{$h}->{eventid}, $db_data->{$h}, 1);
                    push(@{$obj->{JOBS}}, $command)
                      if($command && not grep(/\Q$command/g,@{$obj->{JOBS}}));
                  }
                  # Update duration at database entry
                  $db_data->{$h}->{duration} = $duration;

                  $obj->_updateEvent($db_data->{$h});

                  $updatedState++;
              }
          } 
          $totalDuration += $db_data->{$h}->{duration};
          
          push(@merkIds,$db_data->{$h}->{eventid});

          # delete updated rows from hash
          delete $db_data->{$h};

        } else {
          $waiter->next(++$l,undef, sprintf(gettext("Analyze recording '%s'"), 
                                                     $event->{title}))
              if(ref $waiter);

          # Read VideoDir only at first call
          if(not defined $obj->{FILES}) {
            $obj->{FILES} = [];
            $obj->scandirectory();
          }

          my $anahash = $obj->analyze($event);
          if(ref $anahash eq 'HASH') {
              $totalDuration += $anahash->{Duration};

              if($obj->insert($anahash)) {
                  push(@merkIds,$anahash->{eventid});
                  $insertedData++;
              } else {
                  push(@{$err},$anahash->{title});
              }
          } else {
              push(@{$err},$event->{title});
          }
        }
      }

      if($db_data && scalar keys %$db_data > 0) {
        my @todel;
        foreach my $t (keys %{$db_data}) {
            push(@todel,$db_data->{$t}->{RecordMD5});
        }

        my $sql = sprintf('DELETE FROM RECORDS WHERE RecordMD5 IN (%s)', join(',' => ('?') x @todel)); 
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute(@todel)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
      }
    
    debug sprintf 'Finish .. %d recordings inserted, %d recordings updated, %d recordings removed',
           $insertedData, $updatedState, $db_data ? scalar keys %$db_data : 0;

    $obj->{CapacityTotal} = $totalDuration;
    $obj->{CapacityPercent}  = (100.0 / $total) * ($total - $free)
        if($total && $totalUnit eq $freeUnit);
    $obj->{CapacityFree} = ($totalDuration * 100.0 / $obj->{CapacityPercent})
                             - $obj->{CapacityTotal};

    # Previews im fork erzeugen
    if(scalar @{$obj->{JOBS}}) {
        #Changes made after the fork() won't be visible in the parent process
        my @jobs = @{$obj->{JOBS}};
        $obj->{JOBS} = [];

        defined(my $child = fork()) or return error sprintf("Can't fork : %s",$!);
        if($child == 0) {
            $obj->{dbh}->{InactiveDestroy} = 1;

            while(scalar @jobs > 0) {
                my $command = shift (@jobs);
                lg sprintf('Call cmd "%s" now',
                        $command,
                    );
                my $erg = system("nice -n 19 $command");
            }
            exit 0;
        }
    }

    # alte PreviewDirs loeschen
    foreach my $dir (glob(sprintf('%s/*_shot', $obj->{previewimages}))) {
        my $oldEventNumber = (split('/', $dir))[-1];
        unless(grep(sprintf('%lu_shot',$_) eq $oldEventNumber, @merkIds)) {
            deleteDir($dir);
        }
    }

    # Delete all old EPG entrys without the RecordIds which old as one day.
    if(scalar @merkIds) {
        my $sql = sprintf('DELETE FROM OLDEPG where (UNIX_TIMESTAMP(starttime) + duration) < (UNIX_TIMESTAMP() - 86400) and eventid not in (%s)', join(',' => ('?') x @merkIds)); 
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute(@merkIds)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
    }

   $obj->updated() if($insertedData);

   # last call of waiter
   $waiter->end() if(ref $waiter);

    if(ref $console) {
        $console->start() if(ref $waiter);
        if(scalar @{$err} == 0) {
            $console->message(sprintf(gettext("Write %d recordings in database."), scalar @merkIds));
        } else {
            unshift(@{$err}, sprintf(gettext("Write only %d recordings in database. Can\'t assign %d recordings."), scalar @merkIds , scalar @{$err}));
            lg join("\n", @$err);
            $console->err($err);
        }

        $console->redirect({url => '?cmd=rlist', wait => 1})
            if($console->typ eq 'HTML');
    }
    return 1;
}

# Routine um Callbacks zu registrieren und
# diese nach dem Aktualisieren der Aufnahmen zu starten
# ------------------
sub updated {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $cb = shift || 0;
    my $log = shift || 0;

    if($cb) {
        push(@{$obj->{after_updated}}, [$cb, $log]);
    } else {
        foreach my $CB (@{$obj->{after_updated}}) {
            next unless(ref $CB eq 'ARRAY');
            lg $CB->[1]
                if($CB->[1]);
            &{$CB->[0]}()
                if(ref $CB->[0] eq 'CODE');
        }
    }
}

# ------------------
sub refresh {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;

    my $waiter;
    if(ref $console) {
      if($console->typ eq 'HTML') {
        $waiter = $console->wait(gettext("Get informations from recordings ..."),0,1000,'no');
      } else {
        $console->msg(gettext("Get informations from recordings ..."));
      }
    }

    return $obj->readData($watcher,$console,$waiter,1);
}

# ------------------
sub insert {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $attr = shift || return 0;

    my $sth = $obj->{dbh}->prepare(
    qq|
     REPLACE INTO RECORDS
        (eventid, RecordId, RecordMD5, Path, Prio, Lifetime, State, Marks, Type )
     VALUES (?,?,md5(?),?,?,?,?,?,?)
    |);

    $attr->{Marks} = ""
        if(not $attr->{Marks});

    return $sth->execute(
        $attr->{eventid},
        $attr->{RecordId},
        $attr->{Path},
        $attr->{Path},
        $attr->{Prio},
        $attr->{Lifetime},
        $attr->{State},
        $attr->{Marks},
        $attr->{Type},
    );
}

# ------------------
sub _updateEvent {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $event = shift || return undef;
    
    my $sth = $obj->{dbh}->prepare('UPDATE OLDEPG SET duration=?, starttime=FROM_UNIXTIME(?), addtime=FROM_UNIXTIME(?) where eventid=?');
    if(!$sth->execute($event->{duration},$event->{starttime},$event->{addtime},$event->{eventid})) {
        error sprintf("Can't update Event!: '%s' !",$event->{eventid});
        return undef;
    }
    return $event;
}

# ------------------
sub _updateState {# ------------------
    my $obj = shift || return error ('No Object!');
    my $oldattr = shift || return error ('Missing data');
    my $attr = shift || return error ('No data to replace!');

    my $sth = $obj->{dbh}->prepare('UPDATE RECORDS SET RecordId=?, State=?, addtime=FROM_UNIXTIME(?) where RecordMD5=?');
    return $sth->execute($attr->{id},$attr->{state},time,$oldattr->{RecordMD5});
}

# ------------------
sub analyze {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $recattr = shift || return error ('No data to analyze!');

    lg sprintf('Analyze record "%s" from system',
            $recattr->{title},
        );

    my $info = $obj->videoInfo($recattr->{title}, $recattr->{starttime});
    unless($info && ref $info eq 'HASH') {
      error sprintf("Can't find recording '%s' with id : '%s' !",$recattr->{title}, $recattr->{id});
      return 0;
    }

    my @t = split('~', $recattr->{title});
    my $title = $recattr->{title};
    my $subtitle;
    if(scalar @t > 1) { # Splitt genre~title | subtitle
        my @p = split('/', $info->{path});
        $subtitle = delete $t[-1]
            if(scalar @p > 3 && $p[-2] ne '_');
        $subtitle = undef if(defined $subtitle and $subtitle eq ' ');
        $title = join('~',@t);
    }

    my $event = $obj->SearchEpgId( $recattr->{starttime}, $info->{duration}, $title, $subtitle, $info->{channel} );
    if($event) {
        my $id = $event->{eventid};
        $event->{addtime} = time;
        $event->{duration} = int($info->{duration});
        $event->{starttime} = $recattr->{starttime};
        $event = $obj->_updateEvent($event);
        unless($event) {
          return 0;
        }
    } else {
        # Sollte kein Event gefunden werden so muss dieser in OLDEPG mit
        # den vorhandenen Daten (lstr nummer) eingetragen werden und eine PseudoEventId (min(eventid)-1)
        # erfunden werden ;)
        $event = $obj->createOldEventId($recattr->{id}, $recattr->{starttime}, $info->{duration}, $title, $subtitle, $info);
        unless($event) {
          error sprintf("Can't create Event!: '%s' !",$recattr->{id});
          return 0;
        }
    }

    # Make Preview
    my $command = $obj->videoPreview( $event->{eventid}, $info );
    push(@{$obj->{JOBS}}, $command)
        if($command && not grep(/\Q$command/g,@{$obj->{JOBS}}));

    my $ret = {
        title => $recattr->{title},
        RecordId => $recattr->{id},
        Duration => $info->{duration},
        Start => $recattr->{starttime},
        Path  => $info->{path},
        Prio  => $info->{Prio},
        Lifetime  => $info->{Lifetime},
        eventid => $event->{eventid},
        Type  => $info->{type} || 'UNKNOWN',
        State => $recattr->{state}
    };
    $ret->{Marks} = join(',', @{$info->{marks}})
        if(ref $info->{marks} eq 'ARRAY');
    return $ret;
}

# ------------------
sub videoInfo {
# ------------------
    my $obj     = shift || return error ('No object!' );
    my $title   = shift || return error ('No title!' );
    my $starttime   = shift || return error ('No title!' );

    lg sprintf('Get videoInfo from record "%s"', $title );

    my $month=sprintf("%02d",(localtime($starttime))[4]+1);
    my $day=sprintf("%02d",(localtime($starttime))[3]);
    my $hour=sprintf("%02d",(localtime($starttime))[2]);
    my $minute=sprintf("%02d",(localtime($starttime))[1]);

    my @files;

    $title =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
    $title =~ s/([\/])/\./g; # Replace splash

    foreach my $f (@{$obj->{FILES}})
    {
        push (@files, $f->[0])
            if(grep(/\~$title.*?\d{4}\-$month\-$day\.$hour[\:|\.]$minute.+?\d{3}\.vdr/,$f->[1]));
    }

    unless(scalar @files) {
      error sprintf("Can't assign recording with title: '%s' (%s/%s %s:%s)", $title,$month,$day,$hour,$minute);
      return 0;
    }

    my $status = {};

    # Dateigröße von index.vdr für Aufnahmedauer ermitteln
    if($files[0] && -e $files[0]) {

        my $path = dirname($files[0]);

    	#Splitt 2005-01-16.04:35.88.99.rec
    	my ($year, $month, $day, $hour, $minute, $prio, $lifetime)
             = (basename($path)) =~ /^(\d+)\-(\d+)\-(\d+)\.(\d+)[\:|\.](\d+)\.(\d+)\.(\d+)\.rec/si;
#    	if($year && $month && $day && $hour && $minute && $year >= 1970 && $year < 2038 ) {
#    		@{$status->{mtime}} = localtime(timelocal(0,int($minute),int($hour),$day,$month-1,$year-1900));
#    	} else {
#            my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
#        	    $atime,$mtime,$ctime,$blksize,$blocks) = stat $file;
#    		@{$status->{mtime}} = localtime $mtime;
#    	}
        $status->{Prio} = $prio;
        $status->{Lifetime} = $lifetime;

        $status->{duration} = $obj->_recordinglength($path);

        # Schnittmarken ermitteln
        my $marks = sprintf("%s/marks.vdr", $path);
        if(-r $marks) {
            my $data = load_file($marks)
                or error sprintf("I can't read file '%s'",$marks);
            if($data) {
                foreach my $zeile (split("\n", $data)) {
                    # 0:35:07.09 moved from [0:35:13.24 Logo start] by checkBlackFrameOnMark
                    my ($mark) = $zeile =~ /^(\d+\:\d+\:\d+\.\d+)/sg;
                    push(@{$status->{marks}}, $mark)
                        if(defined $mark);
                }
            }
        }

        # Summary ermitteln
        my $file = sprintf("%s/info.vdr", $path);
           $file = sprintf("%s/summary.vdr", $path ) if(main::getVdrVersion() < 10325);

        $status->{type} = 'UNKNOWN';
        if(-r $file) {
            my $text = load_file($file);

            # Neue Vdr Version 1.3.25!
            if(main::getVdrVersion() >= 10325) {
                my $cmod = main::getModule('CHANNELS');
                foreach my $zeile (split(/[\r\n]/, $text)) {
                    if($zeile =~ /^D\s+(.+)/s) {
                        $status->{summary} = $1;
                        $status->{summary} =~ s/\|/\r\n/g;            # pipe used from vdr as linebreak
                        $status->{summary} =~ s/^\s+//;               # no leading white space
                        $status->{summary} =~ s/\s+$//;               # no trailing white space
                    }
                    elsif($zeile =~ /^C\s+(\S+)/s) {
                        $status->{channel} = $1;
                        $status->{type} = $cmod->getChannelType($status->{channel});
                    }
                    elsif($zeile =~ /^T\s+(.+)$/s) {
                        $status->{title} = $1;
                    }
                    elsif($zeile =~ /^S\s+(.+)$/s) {
                        $status->{subtitle} = $1;
                    }
                    elsif($zeile =~ /^X\s+1\s+(.+)$/s) {
                        $status->{video} = $1;
                    }
                    elsif($zeile =~ /^X\s+2\s+(.+)$/s) {
                        $status->{audio} .= "\n" if($status->{audio});
                        $status->{audio} .= $1;
                    }
                }
            } else {
                $status->{summary} = $text;
            }
        }

        $status->{path} = $path;
    }

    return $status;
}

# ------------------
sub videoPreview {
# ------------------
    my $obj     = shift || return error ('No Object!' );
    my $eventid   = shift || return error ('No eventid!');
    my $info    = shift || return error ('No InfoHash!');
    my $rebuild    = shift || 0;

    if ($obj->{previewcommand} eq 'Nothing') {
        return 0;
    }
    if($info->{type} and $info->{type} eq 'RADIO') {
        return 0;
    }

    # Videodir
    my $vdir = $info->{path};
    if(! -d $vdir ) {
        error sprintf("Missing path ! %s",$!);
        return 0;
    }

    # Save dir
    my $count = $obj->{previewcount};
    my $outdir = sprintf('%s/%lu_shot', $obj->{previewimages}, $eventid);

    # Stop here if enough files present
    my @images = glob("$outdir/*.jpg");
    return 0
      if(scalar @images >= $count && !$rebuild);

    deleteDir($outdir) if(scalar @images && $rebuild);

    # or stop if two log's present, use two logs avoid to early run on current live recording
    my $log = sprintf('%s/preview_1st.log', $outdir);
    if(-e $log) {
      $log = sprintf('%s/preview_2nd.log', $outdir);
      if(-e $log) {
        return 0;
      }
    }

    # Mplayer
    unless(-x $obj->{previewbinary}) {
      error("I can't find executable file as usable preview command !");
      return 0;
    }

    unless(-d $outdir) {
      if(!mkpath($outdir)) {
        error sprintf("Can't mkpath '%s' : %s",$outdir,$!);
        return 0;
      }
    }

    my $tmod = main::getModule('TIMERS');
    my $startseconds = ($tmod->{prevminutes} * 60) * 2;
    my $endseconds = ($tmod->{afterminutes} * 60) * 2;
    my $stepseconds = ($info->{duration} - ($startseconds + $endseconds)) / $count;
	# reduced interval on short movies
	if($stepseconds <= 0 or ($startseconds + ($count * $stepseconds)) > $info->{duration}) {
		$stepseconds = $info->{duration} / ( $count + 2 ) ;
		$startseconds = $stepseconds;
	}

    my @files;
    my @frames;
    if ($obj->{previewcommand} eq 'vdr2jpeg') {

        my $m = ref $info->{marks} eq 'ARRAY' ? scalar(@{$info->{marks}}) : 0;
        if($m > 1 && $info->{duration}) {
            my $total = $info->{duration} * $obj->{framerate};
            my $limit = $count * 4;
            my $x = 2;
            my $y = 1;
            while (scalar @frames < $count && $x < $limit) {
                my $f = int($total / $x * $y); # 1/2, 1/3, 2/3, 1/4, 2/4, 3/4, 1/5, 2/5, 3/5 ...
                for (my $n = 0;$n < $m; $n += 2 ) {
                    my $fin = $obj->_mark2frames(@{$info->{marks}}[$n]);
                    my $fout = $total;
                    $fout = $obj->_mark2frames(@{$info->{marks}}[$n+1]) if($n+1 < $m);

                    if ($f >= $fin && $f <= $fout 
                        && 0 == (grep {$f == $_;} @frames) 
                        ) {
                        push(@frames, $f);
                        last;
                    }
                }
                ++$y;
                if($y >= $x) { $x += 2; $y = 1; }
            }
        }

        my $s = int($startseconds * $obj->{framerate});
        while (scalar @frames < $count) {
            push(@frames, $s);
            $s += int( $stepseconds * $obj->{framerate} );
        }
    } else {
        @files = glob("$vdir/[0-9][0-9][0-9].vdr");
        foreach (@files) { s/(\")/\\$1/g; }
    }

    $vdir =~ s/(\")/\\$1/g;

    my $scalex = 180;
    my $mversions = {
        'MPlayer1.0pre5' => sprintf("%s -noautosub -noconsolecontrols -nosound -nolirc -nojoystick -quiet -vo jpeg -jpeg outdir=\"%s\" -ni -ss %d -sstep %d -vf scale -zoom -xy %d -frames %d \"%s\" >> \"%s\" 2>&1",
                                $obj->{previewbinary}, $outdir, $startseconds / 5, $stepseconds / 5, $scalex, $count, join("\" \"",@files), $log),
        'MPlayer1.0pre6' => sprintf("%s -noautosub -noconsolecontrols -nosound -nolirc -nojoystick -quiet -vo jpeg:outdir=\"%s\" -ni -ss %d -sstep %d -vf scale -zoom -xy %d -frames %d \"%s\" >> \"%s\" 2>&1",
                                $obj->{previewbinary}, $outdir, $startseconds / 5, $stepseconds / 5, $scalex, $count, join("\" \"",@files), $log),
        'vdr2jpeg'       => sprintf("%s -r \"%s\" -f %s -x %d -o \"%s\" >> \"%s\" 2>&1",
                                $obj->{previewbinary}, $vdir, join(" -f ", @frames), $scalex, $outdir, $log),
    };
    return $mversions->{$obj->{previewcommand}};
}


sub _mark2frames{
	my $self = shift;
	my $mark = shift;
	my($h, $m, $s, $f) = split /[:.]/, $mark;
	my $frame = (3600 * $h + 60 * $m + $s) * $self->{framerate} + $f ;
	return $frame;
};

# ------------------
sub SearchEpgId {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $start = shift || return error ('No Start!' );
    my $dur = shift || return;
    my $title = shift || return error ('No Title!' );
    my $subtitle = shift;
    my $channel = shift;    

    my $sth;
    my $bis = int($start + $dur);
    if($subtitle && $channel && $channel ne "") {
        $sth = $obj->{dbh}->prepare(
qq|SELECT * FROM OLDEPG WHERE 
        UNIX_TIMESTAMP(starttime) >= ? 
    AND UNIX_TIMESTAMP(starttime)+duration <= ? 
    AND title = ? 
    AND subtitle = ? 
    AND channel_id = ?|);
        $sth->execute($start,$bis,$title,$subtitle,$channel)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
    } elsif($subtitle) {
        $sth = $obj->{dbh}->prepare(
qq|SELECT * FROM OLDEPG WHERE 
        UNIX_TIMESTAMP(starttime) >= ? 
    AND UNIX_TIMESTAMP(starttime)+duration <= ? 
    AND title = ? 
    AND subtitle = ?|);
        $sth->execute($start,$bis,$title,$subtitle)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
    } else {
        $sth = $obj->{dbh}->prepare(
qq|SELECT * FROM OLDEPG WHERE 
        UNIX_TIMESTAMP(starttime) >= ? 
    AND UNIX_TIMESTAMP(starttime)+duration <= ? 
    AND title = ?|);
        $sth->execute($start,$bis,$title)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
    }
    return 0 if(!$sth);

    my $erg = $sth->fetchrow_hashref();
    return $erg
  		if($erg->{eventid}
	  	  and ( # check for equal subtitle
	  		(not $subtitle and not $erg->{subtitle})
	  		 or (($subtitle and $erg->{subtitle}) and ($subtitle eq $erg->{subtitle}))
	      )
		  );
}

# ------------------
sub createOldEventId {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $id = shift || return error ('No Id!' );
    my $start = shift || return error ('No Starttime!' );
    my $duration = shift || 0;
    my $title = shift || return error ('No Title!' );
    my $subtitle = shift;
    my $info = shift;

#warn($title);
    my $attr = {
        title => $title,
        subtitle => $subtitle,
        description => $info->{summary} || "",
        channel => $info->{channel} || "<undef>",
        duration => $duration,
        starttime => $start,
        video => $info->{video} || "",
        audio => $info->{audio} || "",
        addtime => time
    };

    $attr->{eventid} = $obj->{dbh}->selectrow_arrayref('select max(eventid)+1 from OLDEPG')->[0];
    $attr->{eventid} = 1000000000 if(not defined $attr->{eventid} or $attr->{eventid} < 1000000000 );

    # dumper($attr);

    lg sprintf('Create OldEventId from event "%s" - "%s"',
            $title,
            $subtitle ? $subtitle : '',
        );

    my $sth = $obj->{dbh}->prepare('REPLACE INTO OLDEPG(eventid, title, subtitle, description, channel_id, duration, tableid, starttime, video, audio, addtime) VALUES (?,?,?,?,?,?,?,FROM_UNIXTIME(?),?,?,FROM_UNIXTIME(?))');
    $sth->execute(
        $attr->{eventid},
        $attr->{title},
        $attr->{subtitle},
        $attr->{description},
        $attr->{channel},
        int($attr->{duration}),
        $attr->{tableid},
        $attr->{starttime},
        $attr->{video},
        $attr->{audio},
        $attr->{addtime}
    );

    return $attr;
}

# ------------------
sub display {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $recordid = shift || return $console->err(gettext("No RecordID to display the recording! Please use rdisplay 'rid'"));

    my $start = "e.starttime";
    my $stopp = "FROM_UNIXTIME(UNIX_TIMESTAMP(e.starttime) + e.duration)";

    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");
    $stopp = "UNIX_TIMESTAMP(e.starttime) + e.duration" if($console->typ eq "HTML");

    my $sql = qq|
select
    r.RecordMD5 as RecordId,
    r.eventid,
    e.Duration,
    r.Marks,
    r.Prio,
    r.Lifetime,
    $start as StartTime,
    $stopp as StopTime,
    e.title as Title,
    e.subtitle as SubTitle,
    e.description as Description,
    r.State as New,
    r.Type as Type,
    e.channel_id
from
    RECORDS as r,OLDEPG as e
where
    r.eventid = e.eventid
    and RecordMD5 = ?
|;

    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($recordid)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();

    $obj->_loadreccmds;

    my $param = {
        previews => $obj->getPreviewFiles($erg->{eventid}),
        reccmds => [@{$obj->{reccmds}}],
    };

    my $cmod = main::getModule('CHANNELS');
    $erg->{Channel} = $cmod->ChannelToName($erg->{channel_id})
        if($erg->{channel_id} && $erg->{channel_id} ne "<undef>");
    delete $erg->{channel_id};

    $console->table($erg, $param);
}

# ------------------
sub play {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $recordid = shift || return $console->err(gettext("No RecordID to play the recording! Please use rplay 'rid'"));

    my $sql = qq|SELECT RecordID FROM RECORDS WHERE RecordMD5 = ?|;
    my $sth = $obj->{dbh}->prepare($sql);
    my $rec;
    if(!$sth->execute($recordid)
      || !($rec = $sth->fetchrow_hashref())) {
        return $console->err(sprintf(gettext("RecordID '%s' does not exist in the database!"),$recordid));
    }

    my $cmd = sprintf('PLAY %d begin', $rec->{RecordID});
    return $obj->{svdrp}->scommand($watcher, $console, $cmd);
}

# ------------------
sub cut {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $recordid = shift || return $console->err(gettext("No RecordID to play the recording! Please use rplay 'rid'"));

    my $sql = qq|SELECT RecordID FROM RECORDS WHERE RecordMD5 = ?|;
    my $sth = $obj->{dbh}->prepare($sql);
    my $rec;
    if(!$sth->execute($recordid)
      || !($rec = $sth->fetchrow_hashref())) {
        return $console->err(sprintf(gettext("RecordID '%s' does not exist in the database!"),$recordid));
    }

    my $cmd = sprintf('EDIT %d', $rec->{RecordID});
    return $obj->{svdrp}->scommand($watcher, $console, $cmd);
}

# ------------------
sub list {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $text    = shift || "";
    my $params  = shift;

    my $deep = 1;
    my $folder = scalar (my @a = split('/',$obj->{videodir})) + 1;

    my $select = "e.eventid = r.eventid";
    if($text) {
        $deep   = scalar (my @c = split('~',$text));
        $folder += $deep;
        $deep += 1;

        $text =~ s/\'/\\\'/sg;
        $text =~ s/%/\\%/sg;
        $select .= qq|
AND (
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text'
      OR
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text~%'
)
|;

    }

    my %f = (
        'Id' => umlaute(gettext('Service')),
        'Title' => umlaute(gettext('Title')),
        'Subtitle' => umlaute(gettext('Subtitle')),
        'Duration' => umlaute(gettext('Duration')),
    );

    my $start = "e.starttime";
    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");

    my $sql = qq|
SELECT
    r.RecordMD5 as $f{'Id'},
    r.eventid as __EventId,
    e.title as $f{'Title'},
    e.subtitle as $f{'Subtitle'},
    SUM(e.duration) as $f{'Duration'},
    $start as __RecordStart,
    SUM(State) as __New,
    r.Type as __Type,
    COUNT(*) as __Group,
    SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) as __fulltitle,
    IF(COUNT(*)>1,0,1) as __IsRecording,
    e.description as __description
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    $select
GROUP BY
    SUBSTRING_INDEX(r.Path, '/', IF(Length(e.subtitle)<=0, $folder + 1, $folder))
|;

    my $fields = fields($obj->{dbh}, $sql);

    my $sortby = "__fulltitle";
    $sortby = '__RecordStart'
        if($text);

    $sortby = $params->{sortby}
        if(exists $params->{sortby} && grep(/^$params->{sortby}$/i,@{$fields}));
    $sql .= "order by __IsRecording asc, $sortby";
    if(exists $params->{desc} && $params->{desc} == 1) {
        $sql .= " desc"; }
    else {
        $sql .= " asc"; }

    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    unshift(@$erg, $fields);

    my $param = {
        sortable => 1,
        usage => $obj->{CapacityMessage},
        used => $obj->{CapacityPercent},
        total => $obj->{CapacityTotal},
        free => $obj->{CapacityFree},
        previewcommand => $obj->{previewlistthumbs},
        getPreview => sub{ return $obj->getPreviewFiles(@_) },
    };
    return $console->table($erg, $param);
}

# ------------------
sub search {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $text    = shift || return $obj->list($watcher,$console);
    my $params  = shift;

    my $search = buildsearch("e.title,e.subtitle,e.description",$text);

    my %f = (
        'Id' => umlaute(gettext('Service')),
        'Title' => umlaute(gettext('Title')),
        'Subtitle' => umlaute(gettext('Subtitle')),
        'Duration' => umlaute(gettext('Duration')),
    );

    my $start = "e.starttime";
    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");

    my $sql = qq|
SELECT
    r.RecordMD5 as $f{'Id'},
    r.eventid as __EventId,
    e.title as $f{'Title'},
    e.subtitle as $f{'Subtitle'},
    e.duration as $f{'Duration'},
    $start as __RecordStart ,
    r.State as __New,
    r.Type as __Type,
    0 as __Group,
    CONCAT_WS('~',e.title,e.subtitle) as __fulltitle,
    1 as __IsRecording,
    e.description as __description
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    e.eventid = r.eventid
	AND ( $search )
|;

    my $fields = fields($obj->{dbh}, $sql);

    my $sortby = "e.starttime";
    $sortby = $params->{sortby}
        if(exists $params->{sortby} && grep(/^$params->{sortby}$/i,@{$fields}));
    $sql .= "order by $sortby";
    if(exists $params->{desc} && $params->{desc} == 1) {
        $sql .= " desc"; }
    else {
        $sql .= " asc"; }

    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    unshift(@$erg, $fields);

    my $param = {
        sortable => 1,
        usage => $obj->{CapacityMessage},
        used => $obj->{CapacityPercent},
        total => $obj->{CapacityTotal},
        free => $obj->{CapacityFree},
        previewcommand => $obj->{previewcommand},
        getPreview => sub{ return $obj->getPreviewFiles(@_) },
    };
    return $console->table($erg, $param);
}

# ------------------
sub delete {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $record  = shift || return $console->err(gettext("No Recording ID to delete! Please use rdelete 'id'"));
    my $answer  = shift || 0;

    my @rcs  = split(/_/, $record);
    my @todelete;
    my %rec;
        
    foreach my $item (@rcs) {
        if($item =~ /^all\:(\w+)/i) {
            my $ids = $obj->getGroupIds($1);
            for(@$ids) {
                $rec{$_} = 1;
            }
        } else {
                $rec{$item} = 1;
        }   
    }
    my @recordings = keys %rec;
    
    my $sql = sprintf("SELECT r.RecordId,CONCAT_WS('~',e.title,e.subtitle),r.RecordMD5 FROM RECORDS as r,OLDEPG as e WHERE e.eventid = r.eventid and r.RecordMD5 IN (%s) ORDER BY r.RecordId desc", join(',' => ('?') x @recordings)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@recordings)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_arrayref(); # Query as array to hold ordering !

    foreach my $recording (@$data) {
        # Make hash for better reading
        my $r = {
          Id       => $recording->[0],
          Title    => $recording->[1]
        };

        if(ref $console and $console->{TYP} eq 'CONSOLE') {
            $console->table($r);
            my $confirm = $console->confirm({
                typ   => 'confirm',
                def   => 'y',
                msg   => gettext('Are you sure to delete this recording?'),
            }, $answer);
            next if(! $answer eq 'y');
        }

        debug sprintf('Call delete recording with title "%s", id: %d%s',
            $r->{Title},
            $r->{Id},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );


        $obj->{svdrp}->queue_cmds(sprintf("delr %s",$r->{Id}));
        push(@todelete,$r->{Title}); # Remember title

        # Remove recordings from request, if found in database
        my $i = 0;
        for my $x (@recordings) {
          if ( $x eq $recording->[2] ) { # Remove known MD5 from user request
            splice @recordings, $i, 1;
          } else {
          $i++;
          }
        }
    }
    
    $console->err(sprintf(gettext("Recording with number '%s' does not exist in the database!"), 
      join('\',\'',@recordings))) if(ref $console and scalar @recordings);

    if($obj->{svdrp}->queue_cmds('COUNT')) {

        my $msg = sprintf(gettext("Recording '%s' to delete"),join('\',\'',@todelete));

        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos

        my $waiter;
        if($obj->{svdrp}->err) {
          $console->err($erg) if(ref $console);
        } else {
          if(ref $console) {
              if($console->typ eq 'HTML') {
                $waiter = $console->wait($msg,0,1000,'no');
              }else {
                $console->msg($msg);
              }
          }
        }
        sleep(1);

        $obj->readData($watcher,$console,$waiter);

    } else {
        $console->err(gettext("No recording to delete!"));
    }

    return 1;
}


sub is_empty_dir {
    my $dir    = shift;
    local (*DIR);
    return unless opendir DIR, $dir;
    while (defined($_ = readdir DIR)) {
        next if /^\.\.?$/;
        closedir DIR;
        return 0;
    }
    closedir DIR;
    return 1;
}

# ------------------
sub redit {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $recordid  = shift || return $console->err(gettext("No RecordID to edit!"));
    my $data    = shift || 0;

    my $rec;
    if($recordid) {
        my $sql = qq|
SELECT
    CONCAT_WS('~',e.title,e.subtitle) as title,
    e.eventid as EventId,
    r.Path,
    r.Prio,
    r.Lifetime
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    e.eventid = r.eventid
	AND ( r.RecordMD5 = ? )
|;
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute($recordid)
            or return $console->err(sprintf(gettext("RecordID '%s' does not exist in the database!"),$recordid));
        $rec = $sth->fetchrow_hashref();
    }

    my $file = sprintf("%s/info.vdr", $rec->{Path});

    my $desc;
    my $channel;
    my $video;
    my $audio;

    if(-r $file) {
        my $text = load_file($file) 
        or $console->err(sprintf(gettext("Can't open file '%s' : %s"),$file,$!));

        foreach my $zeile (split(/[\r\n]/, $text)) {
            if($zeile =~ /^D\s+(.+)/s) {
                $desc = $1;
                $desc =~ s/\|/\r\n/g;            # pipe used from vdr as linebreak
                $desc =~ s/^\s+//;               # no leading white space
                $desc =~ s/\s+$//;               # no trailing white space
            }
            elsif($zeile =~ /^C\s+(\S+)/s) {
                $channel = $1;
            }
            elsif($zeile =~ /^X\s+1\s+(.+)$/s) {
                $video = $1;
            }
            elsif($zeile =~ /^X\s+2\s+(.+)$/s) {
                $audio .= "\n" if($audio);
                $audio .= $1;
            }
        }
    }

    my $marksfile = sprintf('%s/%s', $rec->{Path}, 'marks.vdr');
    my $marks = (-r $marksfile ? load_file($marksfile) : '');

  	$rec->{title} =~s#~+#~#g;
	  $rec->{title} =~s#^~##g;
    $rec->{title} =~s#~$##g;

    my $mod = main::getModule('CHANNELS');

    my $questions = [
        'title' => {
            msg     => gettext('Title of recording'),
            def     => $rec->{title},
            req     => gettext("This is required!"),
        },
        'lifetime' => {
            typ     => 'integer',
            msg     => gettext('Lifetime (0 .. 99)'),
            def     => int($rec->{Lifetime}),
            check   => sub{
                my $value = shift || 0;
                if($value >= 0 and $value < 100) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
            req     => gettext("This is required!"),
         },
        'priority' => {
            typ     => 'integer',
            msg     => gettext('Priority (0 .. 99)'),
            def     => int($rec->{Prio}),
            check   => sub{
                my $value = shift || 0;
                if($value >= 0 and $value < 100) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
            req     => gettext("This is required!"),
        },
    		'channel' => {
            typ     => 'list',
            def     => $mod->ChannelToPos($channel),
            choices => sub {
                my $erg = $mod->ChannelArray('Name');
                unshift(@$erg, gettext("Undefined"));                          
                return $erg;
            },
            msg   => gettext('Channel'),
            check   => sub{
                my $value = shift || return;

                if(my $ch = $mod->PosToChannel($value) || $mod->NameToChannel($value) ) {
                    return $ch;
                } elsif( ! $mod->NameToChannel($value)) {
                    return undef, sprintf(gettext("This channel '%s' does not exist!"),$value);
                } else {
                   return undef, gettext("This is required!");
                }
            },
        },
        'summary' => {
            msg   => gettext("Summary"),
            def   => $desc || '',
        },
    		'video' => {
            msg   => gettext('Video'),
            def   => $video,
        },
    		'audio' => {
            msg   => gettext('Audio'),
            def   => $audio,
        },
        'marks' => {
            param => {type => 'text'},
            msg   => gettext("Marks"),
            def   => $marks || '',
        },
    ];

    $data = $console->question(gettext("Edit recording"), $questions, $data);

    if(ref $data eq 'HASH') {
        my $touchVDR = 0;
        my $dropEPGEntry = 0;
        my $ChangeRecordingData = 0;

        debug sprintf('Record "%s" is changed%s',
            $rec->{title},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        if($data->{summary} ne $desc 
          or $data->{channel} ne $channel 
          or $data->{video} ne $video
          or $data->{audio} ne $audio) {
            my $out;
            $data->{summary} =~ s/\r\n/\|/g;            # pipe used from vdr as linebreak
            $data->{summary} =~ s/\n/\|/g;              # pipe used from vdr as linebreak
            $data->{summary} =~ s/^\s+//;               # no leading white space
            $data->{summary} =~ s/\s+$//;               # no trailing white space
            if(-r $file) {
              my $text = load_file($file) 
                or $console->err(sprintf(gettext("Can't open file '%s' : %s"),$file,$!));
              foreach my $zeile (split(/[\r\n]/, $text)) {
                    $zeile =~ s/^\s+//;
                    $zeile =~ s/\s+$//;
                    if($zeile =~ /^D\s+(.+)/s) {
                      if(defined $data->{summary} && $data->{summary}) {
                        $out .= "D ".  $data->{summary} . "\n";
                        undef $data->{summary};
                      }
                    } 
                    elsif($zeile =~ /^C\s+(\S+)/s) {
                      if(defined $data->{channel} && $data->{channel}) {
                        $data->{channel} =~ s/^\s+//;
                        $data->{channel} =~ s/\s+$//;
                        $out .= "C ".  $data->{channel} . "\n" if($data->{channel});
                        undef $data->{channel};
                      }
                    }
                    elsif($zeile =~ /^X\s+1\s+(.+)$/s) {
                      if(defined $data->{video} && $data->{video}) {
                        $data->{video} =~ s/^\s+//;
                        $data->{video} =~ s/\s+$//;
                        $out .= "X 1 ".  $data->{video} . "\n" if($data->{video});
                        undef $data->{video};
                      }
                    }
                    elsif($zeile =~ /^X\s+2\s+(.+)$/s) {
                      if(defined $data->{audio} && $data->{audio}) {
                        foreach my $line (split(/[\r\n]/, $data->{audio})) {
                          $line =~ s/^\s+//;
                          $line =~ s/\s+$//;
                          next unless($line);
                          $out .= "X 2 ". $line  . "\n";
                        }
                        undef $data->{audio};
                      }
                    } else {
                      $out .= $zeile . "\n" if($zeile);
                    }
                }
            }
            if(defined $data->{channel} && $data->{channel}) {
              $data->{channel} =~ s/^\s+//;      
              $data->{channel} =~ s/\s+$//;      
              $out .= "C ".  $data->{channel} . "\n" if($data->{channel});
            }
            if(defined $data->{summary} && $data->{summary}) {
              $out .= "D ".  $data->{summary} . "\n";
            }
            if(defined $data->{video} && $data->{video}) {
              $data->{video} =~ s/^\s+//;        
              $data->{video} =~ s/\s+$//;        
              $out .= "X 1 ".  $data->{video} . "\n" if($data->{video});
            }
            if(defined $data->{audio} && $data->{audio}) {
              foreach my $line (split(/[\r\n]/, $data->{audio})) {
                $line =~ s/^\s+//;               
                $line =~ s/\s+$//;               
                $out .= "X 2 ". $line  . "\n" if($line);
              }
            }

            save_file($file, $out)
               or return $console->err(sprintf(gettext("Can't write file '%s' : %s"),$file,$!));
            $dropEPGEntry = 1;
        }

        if($data->{marks} ne $marks) {
            save_file($marksfile, $data->{marks})
               or return $console->err(sprintf(gettext("Can't write file '%s' : %s"),$marksfile,$!));
            $ChangeRecordingData = 1;
        }


        if($data->{lifetime} ne $rec->{Lifetime}
            or $data->{priority} ne $rec->{Prio}) {

            my @options = split('\.', $rec->{Path});

            $options[-2] = sprintf("%02d",$data->{lifetime})
                if($data->{lifetime} ne $rec->{Lifetime});

            $options[-3] = sprintf("%02d",$data->{priority})
                if($data->{priority} ne $rec->{Prio});

            my $newPath = join('.', @options);

            move($rec->{Path}, $newPath)
                 or return $console->err(sprintf(gettext("Recording: '%s', can't move to '%s' : %s"),$rec->{title},$newPath,$!));

            $rec->{Path} = $newPath;
            $touchVDR = 1;
            $ChangeRecordingData = 1;
        }

	    $data->{title} =~s#~+#~#g;
	    $data->{title} =~s#^~##g;
        $data->{title} =~s#~$##g;

        if($data->{title} ne $rec->{title}) {

            # Rename auf der Platte
            my $newPath = sprintf('%s/%s/%s', $obj->{videodir}, $obj->translate($data->{title}),basename($rec->{Path}));

            my $parentnew = dirname($newPath);
            unless( -d $parentnew) {
                mkpath($parentnew)
                    or return $console->err(sprintf(gettext("Recording: '%s', can't mkpath: '%s' : %s"),$rec->{title},$parentnew,$!));
            }

            move($rec->{Path},$newPath)
                    or return $console->err(sprintf(gettext("Recording: '%s', can't move to '%s' : %s"),$rec->{title},$data->{title},$!));

            my $parentold = dirname($rec->{Path});
            if($obj->{videodir} ne $parentold
                and -d $parentold
                and is_empty_dir($parentold)) {
                rmdir($parentold)
                    or return $console->err(sprintf(gettext("Recording: '%s', can't remove '%s' : %s"),$rec->{title},$parentold,$!));
            }

            $ChangeRecordingData = 1;
            $dropEPGEntry = 1;
            $touchVDR = 1;
        }

        if($dropEPGEntry) { # Delete EpgOld Entrys
            my $sth = $obj->{dbh}->prepare('DELETE FROM OLDEPG WHERE eventid = ?');
            $sth->execute($rec->{EventId})
                or return error sprintf("Can't execute query: %s.",$sth->errstr);
        }

        if($ChangeRecordingData) { 
            my $sth = $obj->{dbh}->prepare('DELETE FROM RECORDS WHERE RecordMD5 = ?');
            $sth->execute($recordid)
                or return error sprintf("Can't execute query: %s.",$sth->errstr);
        }

        if($touchVDR) { #Ab 1.3.11 resync with touch /video/.update
            touch($obj->{videodir}."/.update");
        }

        my $waiter;
        if(ref $console) {
            if($console->typ eq 'HTML') {
              $waiter = $console->wait(gettext('Recording is edited!'),0,1000,'no');
            }else {
              $console->msg(gettext('Recording is edited!'));
            }
        }
        $obj->readData($watcher,$console,$waiter);

        $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
            if(ref $console and $console->typ eq 'HTML');
    }

    return 1;
}

# ------------------
# Load Reccmds's
sub _loadreccmds {
# ------------------
    my $obj = shift || return error ('No Object!' );

    unless($obj->{reccmds}) {
        $obj->{reccmds} = [];
        if(-r $obj->{commandfile} and my $text = load_file($obj->{commandfile})) {
            foreach my $zeile (split(/\n/, $text)) {
                if($zeile !~ /^\#/ and $zeile !~ /^$/ and $zeile !~ /true/) {
                    push(@{$obj->{reccmds}}, $zeile);
                }
            }
        }
    }
}

# ------------------
sub conv {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $data = shift || 0;

    $obj->_loadreccmds;

    unless(scalar @{$obj->{reccmds}}) {
        $console->err(gettext('No reccmds.conf on your System!'));
        return 1;
    }

    unless($data) {
        $console->err(gettext("Please use rconvert 'cmdid_rid'"));
        unshift(@{$obj->{reccmds}}, ['Descr.', 'Command']);
        $console->table($obj->{reccmds});
        $obj->list($watcher, $console);
    }

    my ($cmdid, $recid) = split(/[\s_]/, $data);
    my $cmd = (split(':', $obj->{reccmds}->[$cmdid-1]))[-1] || return $console->err(gettext("I can't find this CommandID"));
    my $path = $obj->IdToPath($recid) || return $console->err(gettext("I can't find this RecordID"));

    debug sprintf('Call command "%s" on record "%s"%s',
        $cmd,
        $path,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    my $call = "$cmd \"$path\"";
    my $output = `$call`;
    if( $? >> 8 > 0) {
        $console->message(sprintf(gettext("Sorry! Call %s %s Error output: %s"), $cmd, $path, $output));
    } else {
        $console->message(sprintf(gettext("Call %s %s With output: %s"), $cmd, $path, $output));
    }
    $console->link({
        text => gettext("Back to recordings list"),
        url => "?cmd=rlist",
    }) if($console->typ eq 'HTML');
    return 1;
}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift;

    my $sql = qq|
SELECT
    r.RecordId as __Id,
    r.eventid as __EventId,
    e.title,
    e.subtitle,
    FROM_UNIXTIME(e.Duration,'%h:%i:%s') as Duration,
    e.starttime as __RecordStart
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    e.eventid = r.eventid
    and UNIX_TIMESTAMP(e.starttime) > ?
ORDER BY
    e.starttime asc
|;
    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($lastReportTime)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);
    return {
        message => sprintf(gettext('%d new recordings since last report time %s'),
                             (scalar @$erg -1), scalar localtime($lastReportTime)),
        table   => $erg,
    };
}


# ------------------
sub IdToPath {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select Path from RECORDS where RecordMD5 = ?');
    $sth->execute($id)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Path} : undef;
}

# ------------------
sub getPreviewFiles {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $id = shift || return error ('No EventID!' );

    # look for pictures
    my $outdir = sprintf('%s/%lu_shot', $obj->{previewimages}, $id);
    if(my @previews = glob("$outdir/[0-9]*.jpg")) {
        splice(@previews,$obj->{previewcount},scalar(@previews))
            if(scalar(@previews) > $obj->{previewcount});
        map {
            $_ =~ s/^$obj->{previewimages}/previewimages/
        } @previews;
        return \@previews;
    } else {
        return undef;
    }
}

# ------------------
sub getGroupIds {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $recid = shift || return error ('No Record ID!' );
    
    my $epgid = getDataById($recid, 'RECORDS', 'RecordMD5');
    if(!$epgid) {
      error sprintf("Can't find Record for id %s!", $recid);
      return;
    }
    my $epgdata = main::getModule('EPG')->getId($epgid->{eventid});

    my  $text    = $epgdata->{title};

    my $deep = 1;
    my $folder = scalar (my @a = split('/',$obj->{videodir})) + 1;

    my $select = "e.eventid = r.eventid";
    if($text) {
        $deep   = scalar (my @c = split('~',$text));
        $folder += $deep;
        $deep += 1;

        $text =~ s/\'/\\\'/sg;
        $text =~ s/%/\\%/sg;
        $select .= qq|
AND (
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text'
      OR
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text~%'
)
|;

    }

    my $sql = qq|
SELECT
    r.RecordMD5
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    $select
GROUP BY
    SUBSTRING_INDEX(r.Path, '/', IF(Length(e.subtitle)<=0, $folder + 1, $folder))
|;

    my $erg = $obj->{dbh}->selectall_arrayref($sql);

    my $ret = [];
    for(@{$erg}) {
        push(@$ret, $_->[0]);
    }
    return $ret;
}


# ------------------
sub translate {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $title = shift || return error ('No Title in translate!');
    my $vfat = shift || $obj->{vfat};

    if($vfat eq 'y')
    {
        $title =~ s/([^üäößa-z0-9\&\!\-\s\.\@\~\,\(\)\%\+])/sprintf('#%X', ord($1))/seig;
        $title =~ s/[^üäößa-z0-9\!\&\-\#\.\@\~\,\(\)\%\+]/_/sig;
        # Windows can't handle '.' at the end of directory names
        $title =~ s/(\.$)/\#2E/sig;
        $title =~ s/(\.~)/\#2E~/sig;
    } else {
        $title =~ s/\'/\x01/sg;
        $title =~ s/\//\x02/sg;
        $title =~ s/ /_/sg;
    }
    $title =~ s/~/\//sg;

    return $title;
}

# ------------------
# Length of recording in seconds,
# return value as integer 
sub _recordinglength {
# ------------------
    my $obj = shift || return 0, error ('No Object!' );
    my $path = shift || return 0, error ('Missing path from recording!' );

    my $f = sprintf("%s/index.vdr", $path);
    my $r = sprintf("%s/001.vdr", $path);

    # Pseudo Recording (DIR)
    return 0 if(! -r $f and ! -s $r);

    if(-r $f) {
        my $bytes = stat($f)->size;
        return int(($bytes / 8) / 25);
    } else {
        error sprintf("Couldn't read : '%s'", $f);
    }
    return 0;
}

# ------------------
sub converttitle {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $title = shift || return error ('No Title in translate!');
    my $vfat = shift || $obj->{vfat};

    if($vfat eq 'y') {
        $title =~ s/\#([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $title =~ s/\x03/:/g; # See backward compat.. at recordings.c
    }

    $title =~ s/\x01/\'/g;
    $title =~ s/\x02/\\/g;

    $title =~ s/_/ /g;
    $title =~ s/\//~/g;

    return $title;
}

# ------------------
sub suggest {# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $search = shift;
    my $params  = shift;

    if($search) {
        my $sql = qq|
    SELECT
        e.title as title
    FROM
        RECORDS as r,
        OLDEPG as e
    WHERE
        e.eventid = r.eventid
    	AND ( e.title LIKE ? )
    GROUP BY
        title
UNION
    SELECT
        e.subtitle as title
    FROM
        RECORDS as r,
        OLDEPG as e
    WHERE
        e.eventid = r.eventid
    	AND ( e.subtitle LIKE ? )
    GROUP BY
        title
ORDER BY
    title
LIMIT 25
        |;
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute('%'.$search.'%','%'.$search.'%')
            or return error "Can't execute query: $sth->errstr.";
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}


1;
