package XXV::MODULES::RECORDS;

use strict;

use Tools;
use File::Find;
use File::Copy;
use File::Path;
use File::Basename;
use File::stat;
use Locale::gettext;
use Linux::Inotify2;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');

    my $args = {
        Name => 'RECORDS',
        Prereq => {
            'Time::Local' => 'efficiently compute time from local and GMT time ',
            'Digest::MD5 qw(md5_hex)' => 'Perl interface to the MD5 Algorithm',
            'Linux::Inotify2' => 'scalable directory/file change notification'
        },
        Description => gettext('This module manages recordings.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $obj->status(@_) },
        Preferences => {
            commandfile => {
                description => sprintf(gettext("Path of file '%s'"),'reccmds.conf'),
                default     => '/var/lib/vdr/reccmds.conf',
                type        => 'file',
                required    => gettext("This is required!"),
            },
            reading => {
                description => gettext('How often recordings are to be updated (in minutes)'),
                default     => 180,
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
                description => gettext('Directory where recordings are stored'),
                default     => '/var/lib/video',
                type        => 'dir',
                required    => gettext("This is required!"),
            },
            previewbinary => {
                description => gettext('Location of used program to produce thumbnails on your system.'),
                default     => '/usr/bin/mplayer',
                type        => 'file',
                required    => gettext("This is required!"),
            },
            previewcommand => {
                description => gettext('The program used to create thumbnails'),
                type        => 'list',
                choices     => [
                    [gettext('None'), 'Nothing'],
                    ['MPlayer1.0pre5', 'MPlayer1.0pre5'],
                    ['MPlayer1.0pre6', 'MPlayer1.0pre6'],
                    ['vdr2jpeg',       'vdr2jpeg'],
                ],
                default     => 'Nothing',
                required    => gettext("This is required!"),
            },
            previewcount => {
                description => gettext('Produce how many thumbnails'),
                default     => 3,
                type        => 'integer',
            },
            previewlistthumbs => {
                description => gettext('Display recording list with thumbnails?'),
                default     => 'n',
                type        => 'confirm',
            },
            previewimages => {
                description => gettext('Common directory for preview images'),
                default     => '/var/cache/xxv/preview',
                type        => 'dir',
                required    => gettext('This is required!'),
            },
            vfat => {
                description => gettext('VDR compiled for VFAT system (VFAT=1)'),
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
                description => gettext('List of recordings'),
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
            rrecover => {
                description => gettext("Recover deleted recordings"),
                short       => 'rru',
                callback    => sub{ $obj->recover(@_) },
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
                description => gettext("Play recording 'rid' in the VDR."),
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
                Descr => gettext('Create event entries if a recording has been deleted.'),

                # You have this choices (harmless is default):
                # 'harmless', 'interesting', 'veryinteresting', 'important', 'veryimportant'
                Level => 'important',

                # Search for a spezial Event.
                # I.e.: Search for an LogEvent with match
                # "Sub=>text" = subroutine =~ /text/
                # "Msg=>text" = logmessage =~ /text/
                # "Mod=>text" = modname =~ /text/
                SearchForEvent => {
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

                            my $title = sprintf(gettext("Recording deleted: %s"), $epg->{title});

                            my $description = "";
                            if($epg->{subtitle}) {
                               $description .= sprintf(gettext("Subtitle: %s"), $epg->{subtitle});
                               $description .= '\r\n';
                            }
                            if($epg->{description}) {
                               $description .= sprintf(gettext("Description: %s"), $epg->{description});
                               $description .= '\r\n';
                            }

                            main::getModule('REPORT')->news($title, $description, "display", $record->{eventid}, $event->{Level});
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
        return panic("\nCouldn't load modul!: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # define framerate PAL 25, NTSC 30
    $self->{framerate} = 25;

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize modul!');

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

    my $version = 26; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows
    if(!tableUpdated($obj->{dbh},'RECORDS',$version,1)) {
        return 0;
    }

    # Look for table or create this table
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS RECORDS (
          eventid bigint unsigned NOT NULL,
          RecordId int unsigned not NULL,
          RecordMD5 varchar(32) NOT NULL,
          Path text NOT NULL,
          Prio tinyint NOT NULL,
          Lifetime tinyint NOT NULL,
          State tinyint NOT NULL,
          FileSize int unsigned default '0', 
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
    $obj->{inotify} = undef;
    $obj->{lastupdate} = 0;

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           return 0;
        }
        $obj->{timers} = main::getModule('TIMERS');
        unless($obj->{timers}) {
           return 0;
        }

        my $updatefile = sprintf("%s/.update",$obj->{videodir});
        if( -r $updatefile) {
          my $inotify = new Linux::Inotify2
            or panic sprintf("Unable to create new inotify object: %s",$!);

          if($inotify) {
            # Bind watch to event::io
            Event->io( 
              fd => $inotify->fileno, 
              poll => 'r', 
              cb => sub { $inotify->poll }
            );
            # watch update file
            $inotify->watch(
                $updatefile, 
                IN_ALL_EVENTS, 
                sub {  my $e = shift; $obj->_notify_readData($e); }
            );
            $obj->{inotify} = 'active';
          }
        }

        # Interval to read recordings and put to DB
        Event->timer(
            interval => $obj->{reading} * 60,
            prio => 6,  # -1 very hard ... 6 very low
            cb => sub {
                my $forceUpdate = ($obj->{countReading} % ( $obj->{fullreading} * 60 / $obj->{reading} ) == 0);
                if($forceUpdate || (time - $obj->{lastupdate}) > ($obj->{reading}/2) ) {
                  $obj->readData(undef,undef,undef,$forceUpdate);
                  $obj->{lastupdate} = time;
                }
                $obj->{countReading} += 1;
            },
        );
        $obj->readData(undef,undef,undef,'force');
        $obj->{countReading} += 1;
        $obj->{lastupdate} = time;
        return 1;
    }, "RECORDS: Store recordings in database ...", 20);

    1;
}

# ------------------
# Callback to reread data if /video/.update changed by VDR 
# trigged by file notifcation from inotify
sub _notify_readData {
# ------------------
  my $obj = shift || return error('No object defined!');
  my $e = shift;
  lg sprintf "notify events for %s:%d received: %x", $e->fullname, $e->cookie, $e->mask;

  if((time - $obj->{lastupdate}) > 15  # Only if last update prior 15 seconds (avoid callback chill)
     && $obj->readData()) {

        $obj->{lastupdate} = time;

        # Update preview images after five minutes
        my $after = ($obj->{timers}->{prevminutes}) * 60 * 2;
        $after = 300 if($after <= 300);

        Event->timer(
        interval => 60,
        after => $after, 
        cb => sub {
          if((time - $obj->{lastupdate}) >= ($after - 30)) {
              if($obj->readData()) {
                $obj->{lastupdate} = time;
              }
              $_[0]->w->cancel;
            }
          }
        );
    }
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
    my $obj = shift || return error('No object defined!');
    my $vdata = shift || return error('No data defined!');
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
          error sprintf("Couldn't parse svdrp data : '%s'",$record);
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
        %{$dataHash->{lc($hash)}} = %{$event};
    }
    return ($dataHash);
}

# ------------------
sub scandirectory {
# ------------------
    my $obj = shift || return error('No object defined!');

    find(
            {
                wanted => sub{
                    if(-r $File::Find::name) {
                        push(@{$obj->{FILES}},[$File::Find::name,$obj->converttitle($File::Find::name)])
                            if($File::Find::name =~ /\.rec\/\d{3}.vdr$/sig);  # Lookup for *.rec/001.vdr
                    } else {
                        lg "Permissions deny, Couldn't read : $File::Find::name";
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $waiter = shift;
    # Read manual or Once at day, make full scan
    my $forceUpdate = shift;

    # Read recording over SVDRP
    my $lstr = $obj->{svdrp}->command('lstr');
    my $vdata = [ grep(/^250/, @$lstr) ];

    unless(scalar @$vdata) {
        # Delete old Records
        $obj->{dbh}->do('DELETE FROM RECORDS');

        my $msg = gettext('No recordings available!');
        con_err($console,$msg);
        return;
    }

    # Get state from used harddrive (/video)
    my $stat = $obj->{svdrp}->command('stat disk');
    my ($total, $totalUnit, $free, $freeUnit, $percent);    
    my $totalDuration = 0;
    my $totalSpace = 0;

    if($stat->[1] and $stat->[1] =~ /^250/s) {
        #250 473807MB 98028MB 79%
        ($total, $totalUnit, $free, $freeUnit, $percent)
            = $stat->[1] =~ /^250[\-|\s](\d+)(\S+)\s+(\d+)(\S+)\s+(\S+)/s;

        $obj->{CapacityMessage} = sprintf(gettext("Used %s, total %s%s, free %s%s"),$percent, dot1000($total), $totalUnit,  dot1000($free), $freeUnit);
        $obj->{CapacityPercent} = int($percent);

    } else {
        error("Couldn't get disc state : ".join("\n", @$stat));
        $obj->{CapacityMessage} = gettext("Unknown disc capacity!");
        $obj->{CapacityPercent} = 0;

    }

    my @merkMD5;
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
    if($forceUpdate) {
        $obj->{dbh}->do('DELETE FROM RECORDS');
    } else {
        # read database for compare with vdr data
        my $sql = qq|SELECT SQL_CACHE  r.eventid as eventid, r.RecordId as id, 
                        UNIX_TIMESTAMP(e.starttime) as starttime, 
                        e.duration as duration, r.State as state, 
                        CONCAT_WS("~",e.title,e.subtitle) as title, 
                        LOWER(CONCAT_WS("~",e.title,e.subtitle,UNIX_TIMESTAMP(e.starttime))) as hash,
                        UNIX_TIMESTAMP(e.addtime) as addtime,
                        r.Path as path,
                        r.Type as type,
                        r.FileSize,
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
          if(($db_data->{$h}->{starttime} + $db_data->{$h}->{duration} + 7200) > $db_data->{$h}->{addtime}) {
              my $duration = $obj->_recordinglength($db_data->{$h}->{path});
              if($duration != $db_data->{$h}->{duration}) {

                  # Update duration at database entry
                  $db_data->{$h}->{duration} = $duration;
                  $db_data->{$h}->{FileSize} = $obj->_recordingsize($db_data->{$h}->{path}, ($duration * 8 * $obj->{framerate}));

                  # set addtime only if called from EVENT::TIMER
                  # avoid generating preview image during user actions
                  # it's should speedup reading recordings
                  unless($console) {
                      $db_data->{$h}->{addtime} = time;
                      # Make preview and remove older Preview images
                      my $command = $obj->videoPreview( $db_data->{$h}, 1);
                      push(@{$obj->{JOBS}}, $command)
                        if($command && not grep(/\Q$command/g,@{$obj->{JOBS}}));
                  }
                  $obj->_updateEvent($db_data->{$h});
                  $obj->_updateFileSize($db_data->{$h});

                  $updatedState++;
              }
          }

          $totalDuration += $db_data->{$h}->{duration};
          $totalSpace += $db_data->{$h}->{FileSize};
          
          push(@merkMD5,$db_data->{$h}->{RecordMD5});

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
              $totalSpace += $anahash->{FileSize};

              if($obj->insert($anahash)) {
                  push(@merkMD5,$anahash->{RecordMD5});
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
            or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
      }

    my $removedData = $db_data ? scalar keys %$db_data : 0;
    debug sprintf 'Finish .. %d recordings inserted, %d recordings updated, %d recordings removed',
           $insertedData, $updatedState, $removedData;


    error sprintf("Unsupported unit '%s' to calc free capacity",$freeUnit) unless($freeUnit eq 'MB');
    # use store capacity and recordings length to calc free capacity
    $obj->{CapacityTotal} = $totalDuration;
    if($totalSpace > 1) {
      $obj->{CapacityFree} = ($free * $totalDuration) / $totalSpace;
    } else {
      $obj->{CapacityFree} = $free * 3600 / 2000; # use 2GB at one hour as base
    }
    $obj->{CapacityPercent}  = ($totalSpace * 100 / ($free + $totalSpace))
      unless($obj->{CapacityPercent});

    # Previews im fork erzeugen
    if(scalar @{$obj->{JOBS}}) {
        #Changes made after the fork() won't be visible in the parent process
        my @jobs = @{$obj->{JOBS}};
        $obj->{JOBS} = [];

        defined(my $child = fork()) or return con_err($console, sprintf("Couldn't fork : %s",$!));
        if($child == 0) {
            $obj->{dbh}->{InactiveDestroy} = 1;

            while(scalar @jobs > 0) {
                my $command = shift (@jobs);
                lg sprintf('Call command "%s"', $command );
                my $erg = system("nice -n 19 $command");
            }
            exit 0;
        }
    }

    # alte PreviewDirs loeschen
    foreach my $dir (glob(sprintf('%s/*_shot', $obj->{previewimages}))) {
        my $basedir = basename($dir);
        unless(grep(sprintf('%s_shot',$_) eq $basedir, @merkMD5)) {
            lg sprintf("Remove old preview files : '%s'",$dir);
            deleteDir($dir);
        }
    }

    # Delete all old EPG entrys
    if($forceUpdate || $removedData) {
        my $sqldeleteEvents = qq|
DELETE FROM OLDEPG 
  WHERE 
  (UNIX_TIMESTAMP(starttime) + duration) < (UNIX_TIMESTAMP() - 86400) 
  and eventid not in 
      ( SELECT eventid FROM RECORDS )
|;
      $obj->{dbh}->do($sqldeleteEvents)
        or error sprintf("Couldn't execute query: %s, %s.",$sqldeleteEvents, $DBI::errstr);
   }

   $obj->updated() if($insertedData);

   # last call of waiter
   $waiter->end() if(ref $waiter);

    $console->start() if(ref $waiter && ref $console);
    if(scalar @{$err} == 0) {
        $console->message(sprintf(gettext("Write %d recordings to the database."), scalar @merkMD5)) if(ref $console);
    } else {
        unshift(@{$err}, sprintf(gettext("Write %d recordings to the database. Couldn't assign %d recordings."), scalar @merkMD5 , scalar @{$err}));
        con_err($console,$err);
    }
    return (scalar @{$err} == 0);
}

# Routine um Callbacks zu registrieren und
# diese nach dem Aktualisieren der Aufnahmen zu starten
# ------------------
sub updated {
# ------------------
    my $obj = shift || return error('No object defined!');
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    my $waiter;
    if(ref $console && $console->typ eq 'HTML') {
      $waiter = $console->wait(gettext("Get information on recordings ..."),0,1000,'no');
    } else {
      con_msg($console,gettext("Get information on recordings ..."));
    }

    if($obj->readData($watcher,$console,$waiter,'force')) {

      $console->redirect({url => '?cmd=rlist', wait => 1})
          if(ref $console and $console->typ eq 'HTML');

      return 1;
    }
    return 0;
}

# ------------------
sub insert {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $attr = shift || return 0;

    my $sth = $obj->{dbh}->prepare(
    qq|
     REPLACE INTO RECORDS
        (eventid, RecordId, RecordMD5, Path, Prio, Lifetime, State, FileSize, Marks, Type )
     VALUES (?,?,?,?,?,?,?,?,?,?)
    |);

    $attr->{Marks} = ""
        if(not $attr->{Marks});

    return $sth->execute(
        $attr->{eventid},
        $attr->{RecordId},
        $attr->{RecordMD5},
        $attr->{Path},
        $attr->{Prio},
        $attr->{Lifetime},
        $attr->{State},
        $attr->{FileSize},
        $attr->{Marks},
        $attr->{Type},
    );
}

# ------------------
sub _updateEvent {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $event = shift || return undef;
    
    my $sth = $obj->{dbh}->prepare('UPDATE OLDEPG SET duration=?, starttime=FROM_UNIXTIME(?), addtime=FROM_UNIXTIME(?) where eventid=?');
    if(!$sth->execute($event->{duration},$event->{starttime},$event->{addtime},$event->{eventid})) {
        error sprintf("Couldn't update event!: '%s' !",$event->{eventid});
        return undef;
    }
    return $event;
}

# ------------------
sub _updateState {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $oldattr = shift || return error ('No data defined!');
    my $attr = shift || return error ('No data to replace!');

    my $sth = $obj->{dbh}->prepare('UPDATE RECORDS SET RecordId=?, State=?, addtime=FROM_UNIXTIME(?) where RecordMD5=?');
    return $sth->execute($attr->{id},$attr->{state},time,$oldattr->{RecordMD5});
}

# ------------------
sub _updateFileSize {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $attr = shift || return error ('No data to replace!');

    my $sth = $obj->{dbh}->prepare('UPDATE RECORDS SET FileSize=?, addtime=FROM_UNIXTIME(?) where RecordMD5=?');
    return $sth->execute($attr->{FileSize},time,$attr->{RecordMD5});
}

# ------------------
sub analyze {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $recattr = shift || return error ('No data to analyze!');

    lg sprintf('Analyze recording "%s"',
            $recattr->{title},
        );

    my $info = $obj->videoInfo($recattr->{title}, $recattr->{starttime});
    unless($info && ref $info eq 'HASH') {
      error sprintf("Couldn't find recording '%s' with id : '%s' !",$recattr->{title}, $recattr->{id});
      return 0;
    }

    my $event = $obj->SearchEpgId( $recattr->{starttime}, $info->{duration}, $recattr->{title}, $info->{channel} );
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
        my @t = split('~', $recattr->{title});
        my $title = $recattr->{title};
        my $subtitle;
        if(scalar @t > 1) { # Splitt genre~title | subtitle
            $subtitle = delete $t[-1];
            $title = join('~',@t);
        }

        $event = $obj->createOldEventId($recattr->{id}, $recattr->{starttime}, $info->{duration}, $title, $subtitle, $info);
        unless($event) {
          error sprintf("Couldn't create event!: '%s' !",$recattr->{id});
          return 0;
        }
    }

    # Make Preview
    my $command = $obj->videoPreview( $info );
    push(@{$obj->{JOBS}}, $command)
        if($command && not grep(/\Q$command/g,@{$obj->{JOBS}}));

    my $ret = {
        RecordMD5 => $info->{RecordMD5},
        title => $recattr->{title},
        RecordId => $recattr->{id},
        Duration => $info->{duration},
        Start => $recattr->{starttime},
        Path  => $info->{path},
        Prio  => $info->{Prio},
        Lifetime  => $info->{Lifetime},
        eventid => $event->{eventid},
        Type  => $info->{type} || 'UNKNOWN',
        State => $recattr->{state},
        FileSize => $info->{FileSize}
    };
    $ret->{Marks} = join(',', @{$info->{marks}})
        if(ref $info->{marks} eq 'ARRAY');
    return $ret;
}

# ------------------
sub videoInfo {
# ------------------
    my $obj     = shift || return error('No object defined!');
    my $title   = shift || return error('No title defined!');
    my $starttime   = shift || return error('No start time defined!');

    lg sprintf('Get information from recording "%s"', $title );

    my @ltime = localtime($starttime);
    my $month=sprintf("%02d",$ltime[4]+1);
    my $day=sprintf("%02d",$ltime[3]);
    my $hour=sprintf("%02d",$ltime[2]);
    my $minute=sprintf("%02d",$ltime[1]);

    my @files;

    $title =~ s/([\)\(\-\?\+\*\[\]\{\}])/\\$1/g; # Replace regex groupsymbols "),(,-,?,+,*,[,],{,}"
    $title =~ s/([\/])/\./g; # Replace splash

    foreach my $f (@{$obj->{FILES}})
    {
        push (@files, $f->[0])
            if(grep(/\~$title.*?\d{4}\-$month\-$day\.$hour[\:|\.]$minute.+?\d{3}\.vdr/,$f->[1]));
    }

    unless(scalar @files) {
      error sprintf("Couldn't assign recording with title: '%s' (%s/%s %s:%s)", $title,$month,$day,$hour,$minute);
      return 0;
    }

    my $status;

    # Dateigröße von index.vdr für Aufnahmedauer ermitteln
    if($files[0] && -e $files[0]) {

      my $path = dirname($files[0]);

    	#Splitt 2005-01-16.04:35.88.99.rec
    	my ($year, $month, $day, $hour, $minute, $prio, $lifetime)
             = (basename($path)) =~ /^(\d+)\-(\d+)\-(\d+)\.(\d+)[\:|\.](\d+)\.(\d+)\.(\d+)\.rec/si;

      $status->{Prio} = $prio;
      $status->{Lifetime} = $lifetime;

      $status->{duration} = $obj->_recordinglength($path);
      $status->{FileSize} = $obj->_recordingCapacity(\@files,($status->{duration} * 8 * $obj->{framerate}));

      my $info = $obj->readinfo($path);    
      foreach my $h (keys %{$info}) { $status->{$h} = $info->{$h}; }
      my $marks = $obj->readmarks($path);
      foreach my $m (keys %{$marks}) { $status->{$m} = $marks->{$m}; }

      $status->{path} = $path;
      $status->{RecordMD5} = md5_hex($path);
    }
    return $status;
}

#-------------------------------------------------------------------------------
# get cut marks from marks.vdr
sub readmarks {
    my $obj     = shift || return error('No object defined!');
    my $path    = shift || return error ('No recording path defined!');

    my $status;
    # Schnittmarken ermitteln
    my $marks = sprintf("%s/marks.vdr", $path);
    if(-r $marks) {
        my $data = load_file($marks)
            or error sprintf("Couldn't read file '%s'",$marks);
        if($data) {
            foreach my $zeile (split("\n", $data)) {
                # 0:35:07.09 moved from [0:35:13.24 Logo start] by checkBlackFrameOnMark
                my ($mark) = $zeile =~ /^(\d+\:\d+\:\d+\.\d+)/sg;
                push(@{$status->{marks}}, $mark)
                    if(defined $mark);
            }
        }
    }
    return $status;
}

#-------------------------------------------------------------------------------
# get information about recording from info.vdr
sub readinfo {
    my $obj     = shift || return error('No object defined!');
    my $path    = shift || return error ('No recording path defined!');

    my $info;
    $info->{type} = 'UNKNOWN'; #TV / RADIO

    # get description
    my $file = sprintf("%s/info.vdr", $path);
    if(-r $file) {
        my $text = load_file($file);
        my $cmod = main::getModule('CHANNELS');
        foreach my $zeile (split(/[\r\n]/, $text)) {
            if($zeile =~ /^D\s+(.+)/s) {
                $info->{description} = $1;
                $info->{description} =~ s/\|/\r\n/g;            # pipe used from vdr as linebreak
                $info->{description} =~ s/^\s+//;               # no leading white space
                $info->{description} =~ s/\s+$//;               # no trailing white space
            }
            elsif($zeile =~ /^C\s+(\S+)/s) {
                $info->{channel} = $1;
                $info->{type} = $cmod->getChannelType($info->{channel});
            }
            elsif($zeile =~ /^T\s+(.+)$/s) {
                $info->{title} = $1;
            }
            elsif($zeile =~ /^S\s+(.+)$/s) {
                $info->{subtitle} = $1;
            }
            elsif($zeile =~ /^X\s+1\s+(.+)$/s) {
                $info->{video} = $1;
            }
            elsif($zeile =~ /^X\s+2\s+(.+)$/s) {
                $info->{audio} .= "\n" if($info->{audio});
                $info->{audio} .= $1;
            }
        }
    }
    return $info;
}
#-------------------------------------------------------------------------------
# store information about recording into info.vdr
sub saveinfo {
    my $obj     = shift || return error('No object defined!');
    my $path    = shift || return error ('No recording path defined!');
    my $info    = shift || return error ('No information defined!');

    my $out;
    foreach my $h (keys %{$info}) {
      $info->{$h} =~ s/\r\n/\|/g;            # pipe used from vdr as linebreak
      $info->{$h} =~ s/\n/\|/g;              # pipe used from vdr as linebreak
      $info->{$h} =~ s/^\s+//;               # no leading white space
      $info->{$h} =~ s/\s+$//;               # no trailing white space
    }

    my $file = sprintf("%s/info.vdr", $path);              
    my $text = ( -r $file ? load_file($file) : '');
    foreach my $zeile (split(/[\r\n]/, $text)) {
        $zeile =~ s/^\s+//;
        $zeile =~ s/\s+$//;
        if($zeile =~ /^T\s+(.+)/s) {
          if(defined $info->{title} && $info->{title}) {
            $out .= "T ".  $info->{title} . "\n";
            undef $info->{title};
          }
        } 
        elsif($zeile =~ /^S\s+(.+)/s) {
          if(defined $info->{subtitle} && $info->{subtitle}) {
            $out .= "S ".  $info->{subtitle} . "\n";
            undef $info->{subtitle};
          }
        } 
        elsif($zeile =~ /^D\s+(.+)/s) {
          if(defined $info->{description} && $info->{description}) {
            $out .= "D ".  $info->{description} . "\n";
            undef $info->{description};
          }
        } 
        elsif($zeile =~ /^C\s+(\S+)/s) {
          if(defined $info->{channel} && $info->{channel}) {
            $out .= "C ".  $info->{channel} . "\n" if($info->{channel});
            undef $info->{channel};
          }
        }
        elsif($zeile =~ /^X\s+1\s+(.+)$/s) {
          if(defined $info->{video} && $info->{video}) {
            $out .= "X 1 ".  $info->{video} . "\n" if($info->{video});
            undef $info->{video};
          }
        }
        elsif($zeile =~ /^X\s+2\s+(.+)$/s) {
          if(defined $info->{audio} && $info->{audio}) {
            foreach my $line (split(/\|/, $info->{audio})) {
              $line =~ s/^\s+//;
              $line =~ s/\s+$//;
              next unless($line);
              $out .= "X 2 ". $line  . "\n";
            }
            undef $info->{audio};
          }
        } else {
          $out .= $zeile . "\n" if($zeile);
        }
    }

    if(defined $info->{title} && $info->{title}) {
      $out .= "T ".  $info->{title} . "\n";
    }
    if(defined $info->{subtitle} && $info->{subtitle}) {
      $out .= "S ".  $info->{subtitle} . "\n";
    }
    if(defined $info->{channel} && $info->{channel}) {
      $out .= "C ".  $info->{channel} . "\n" if($info->{channel});
    }
    if(defined $info->{description} && $info->{description}) {
      $out .= "D ".  $info->{description} . "\n";
    }
    if(defined $info->{video} && $info->{video}) {
      $out .= "X 1 ".  $info->{video} . "\n" if($info->{video});
    }
    if(defined $info->{audio} && $info->{audio}) {
      foreach my $line (split(/\|/, $info->{audio})) {
        $line =~ s/^\s+//;               
        $line =~ s/\s+$//;               
        $out .= "X 2 ". $line  . "\n" if($line);
      }
    }

    return save_file($file, $out);
}


#-------------------------------------------------------------------------------
sub qquote {
    my $str = shift;
    $str =~ s/(\')/\'\\\'\'/g;

#    $metas = '!$`' unless($metas);
#    $metas =~ s/\]/\\]/g;
#    $str =~ s/([$metas])/\\$1/g;

    return "'$str'";
}

# ------------------
sub videoPreview {
# ------------------
    my $obj     = shift || return error('No object defined!');
    my $info    = shift || return error ('No information defined!');
    my $rebuild = shift || 0;

    if ($obj->{previewcommand} eq 'Nothing') {
        return 0;
    }
    if($info->{type} and $info->{type} eq 'RADIO') {
        return 0;
    }
    # Mplayer
    unless(-x $obj->{previewbinary}) {
      error("Couldn't find executable file as usable preview command!");
      return 0;
    }

    # Videodir
    my $vdir = $info->{path};
    if(! -d $vdir ) {
        error sprintf("Missing path ! %s",$!);
        return 0;
    }

    my $outdir = sprintf('%s/%s_shot', $obj->{previewimages}, $info->{RecordMD5});

    my $count = $obj->{previewcount};
    # Stop here if enough files present
    my @images = glob("$outdir/*.jpg");
    return 0
      if(scalar @images >= $count && !$rebuild);

    my $startseconds = ($obj->{timers}->{prevminutes} * 60) * 2;
    my $endseconds = ($obj->{timers}->{afterminutes} * 60) * 2;
    my $stepseconds = ($info->{duration} - ($startseconds + $endseconds)) / $count;
  	# reduced interval on short movies
  	if($stepseconds <= 0 or ($startseconds + ($count * $stepseconds)) > $info->{duration}) {
  		$stepseconds = $info->{duration} / ( $count + 2 ) ;
  		$startseconds = $stepseconds;
  	}

    if($info->{duration} <= $count or $stepseconds <= 1) {  # dont' create to early ?
        lg sprintf("Recording just started, create images for '%s' later.", $info->{title});
        return 0;
    }

    deleteDir($outdir) if(scalar @images && $rebuild);

    # or stop if log's present
    my $log = sprintf('%s/preview.log', $outdir);
    if(-e $log) {
        return 0;
    }

    unless(-d $outdir) {
      if(!mkpath($outdir)) {
        error sprintf("Couldn't make path '%s' : %s",$outdir,$!);
        return 0;
      }
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
        foreach (@files) { $_ = qquote($_); }
    }

    my $scalex = 180;
    my $mversions = {
      'MPlayer1.0pre5' => sprintf("%s -noautosub -noconsolecontrols -nosound -nolirc -nojoystick -quiet -vo jpeg -jpeg outdir=%s -ni -ss %d -sstep %d -vf scale -zoom -xy %d -frames %d %s >> %s 2>&1",
                              $obj->{previewbinary}, qquote($outdir), $startseconds / 5, $stepseconds / 5, $scalex, $count, join(' ',@files), qquote($log)),
      'MPlayer1.0pre6' => sprintf("%s -noautosub -noconsolecontrols -nosound -nolirc -nojoystick -quiet -vo jpeg:outdir=%s -ni -ss %d -sstep %d -vf scale -zoom -xy %d -frames %d %s >> %s 2>&1",
                              $obj->{previewbinary}, qquote($outdir), $startseconds / 5, $stepseconds / 5, $scalex, $count, join(' ',@files), qquote($log)),
      'vdr2jpeg'       => sprintf("%s -r %s -f %s -x %d -o %s >> %s 2>&1",
                              $obj->{previewbinary}, qquote($vdir), join(' -f ', @frames), $scalex, qquote($outdir), qquote($log)),
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
    my $obj = shift || return error('No object defined!');
    my $start = shift || return error('No start time defined!');
    my $dur = shift || return 0;
    my $title = shift || return error('No title defined!');
    my $channel = shift;    

    my $sth;
    my $bis = int($start + $dur);
    if($channel && $channel ne "") {
        $sth = $obj->{dbh}->prepare(
qq|SELECT SQL_CACHE * FROM OLDEPG WHERE 
        UNIX_TIMESTAMP(starttime) >= ? 
    AND UNIX_TIMESTAMP(starttime)+duration <= ? 
    AND CONCAT_WS("~",title,subtitle) = ?
    AND channel_id = ?|);
        $sth->execute($start,$bis,$title,$channel)
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    } else {
        $sth = $obj->{dbh}->prepare(
qq|SELECT SQL_CACHE * FROM OLDEPG WHERE 
        UNIX_TIMESTAMP(starttime) >= ? 
    AND UNIX_TIMESTAMP(starttime)+duration <= ? 
    AND CONCAT_WS("~",title,subtitle) = ?|);
        $sth->execute($start,$bis,$title)
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    }
    return 0 if(!$sth);

    my $erg = $sth->fetchrow_hashref();
    return $erg;
}

# ------------------
sub createOldEventId {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $id = shift || return error('No eventid defined!');
    my $start = shift || return error('No start time defined!');
    my $duration = shift || 0;
    my $title = shift || return error('No title defined!');
    my $subtitle = shift;
    my $info = shift;

    my $attr = {
        title => $title,
        subtitle => $subtitle,
        description => $info->{description} || "",
        channel => $info->{channel} || "<undef>",
        duration => $duration,
        starttime => $start,
        video => $info->{video} || "",
        audio => $info->{audio} || "",
        addtime => time
    };

    $attr->{eventid} = $obj->{dbh}->selectrow_arrayref('SELECT SQL_CACHE  max(eventid)+1 from OLDEPG')->[0];
    $attr->{eventid} = 1000000000 if(not defined $attr->{eventid} or $attr->{eventid} < 1000000000 );

    lg sprintf('Create event "%s" into OLDEPG', $subtitle ? $title .'~'. $subtitle : $title);

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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recordid = shift;

    unless($recordid) {
        con_err($console,gettext("No recording defined for display! Please use rdisplay 'rid'"));
        return;
    }

    my $start = "e.starttime";
    my $stopp = "FROM_UNIXTIME(UNIX_TIMESTAMP(e.starttime) + e.duration)";

    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");
    $stopp = "UNIX_TIMESTAMP(e.starttime) + e.duration" if($console->typ eq "HTML");

    my $sql = qq|
SELECT SQL_CACHE 
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

    my $rec;
    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    if(!$sth->execute($recordid)
      || !($rec = $sth->fetchrow_hashref())) {
        con_err($console,sprintf(gettext("Recording '%s' does not exist in the database!"),$recordid));
        return;
    }

    $obj->_loadreccmds;

    my $param = {
        previews => $obj->getPreviewFiles($rec->{RecordId}),
        reccmds => [@{$obj->{reccmds}}],
    };

    my $cmod = main::getModule('CHANNELS');
    $rec->{Channel} = $cmod->ChannelToName($rec->{channel_id})
        if($rec->{channel_id} && $rec->{channel_id} ne "<undef>");
    delete $rec->{channel_id};

    $console->table($rec, $param);
}

# ------------------
sub play {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recordid = shift || return con_err($console,gettext("No recording defined for playback! Please use rplay 'rid'."));

    my $sql = qq|SELECT SQL_CACHE RecordID,RecordMD5 FROM RECORDS WHERE RecordMD5 = ?|;
    my $sth = $obj->{dbh}->prepare($sql);
    my $rec;
    if(!$sth->execute($recordid)
      || !($rec = $sth->fetchrow_hashref())) {
        return con_err($console,sprintf(gettext("Recording '%s' does not exist in the database!"),$recordid));
    }

    my $cmd = sprintf('PLAY %d begin', $rec->{RecordID});
    if($obj->{svdrp}->scommand($watcher, $console, $cmd)) {

      $console->redirect({url => sprintf('?cmd=rdisplay&data=%s',$rec->{RecordMD5}), wait => 1})
          if(ref $console and $console->typ eq 'HTML');

      return 1;
    }
    return 0;
}

# ------------------
sub cut {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recordid = shift || return con_err($console,gettext("No recording defined for playback! Please use rplay 'rid'."));

    my $sql = qq|SELECT SQL_CACHE RecordID,RecordMD5 FROM RECORDS WHERE RecordMD5 = ?|;
    my $sth = $obj->{dbh}->prepare($sql);
    my $rec;
    if(!$sth->execute($recordid)
      || !($rec = $sth->fetchrow_hashref())) {
        return con_err($console,sprintf(gettext("Recording '%s' does not exist in the database!"),$recordid));
    }

    my $cmd = sprintf('EDIT %d', $rec->{RecordID});
    if($obj->{svdrp}->scommand($watcher, $console, $cmd)) {

      $console->redirect({url => sprintf('?cmd=rdisplay&data=%s',$rec->{RecordMD5}), wait => 1})
          if(ref $console and $console->typ eq 'HTML');

      return 1;
    }
    return 0;
}

# ------------------
sub list {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text    = shift || "";
    my $params  = shift;

    my $deep = 1;
    my $folder = scalar (my @a = split('/',$obj->{videodir})) + 1;

    my $where = "e.eventid = r.eventid";
    if($text) {
        $deep   = scalar (my @c = split('~',$text));
        $folder += $deep;
        $deep += 1;

        $text =~ s/\'/\\\'/sg;
        $text =~ s/%/\\%/sg;
        $where .= qq|
AND (
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text'
      OR
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text~%'
)
|;

    }

    my %f = (
        'Id' => gettext('Service'),
        'Title' => gettext('Title'),
        'Subtitle' => gettext('Subtitle'),
        'Duration' => gettext('Duration')
    );

    my $start = "e.starttime";
    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");

    my $sql = qq|
SELECT SQL_CACHE 
    r.RecordMD5 as \'$f{'Id'}\',
    r.eventid as __EventId,
    e.title as \'$f{'Title'}\',
    e.subtitle as \'$f{'Subtitle'}\',
    SUM(e.duration) as \'$f{'Duration'}\',
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
    $where 
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text    = shift || return $obj->list($watcher,$console);
    my $params  = shift;

    my $query = buildsearch("e.title,e.subtitle,e.description",$text);
    my $search = $query->{query};
    my $term = $query->{term};

    my %f = (
        'Id' => gettext('Service'),
        'Title' => gettext('Title'),
        'Subtitle' => gettext('Subtitle'),
        'Duration' => gettext('Duration')
    );

    my $start = "e.starttime";
    $start = "UNIX_TIMESTAMP(e.starttime)" if($console->typ eq "HTML");

    my $sql = qq|
SELECT SQL_CACHE 
    r.RecordMD5 as \'$f{'Id'}\',
    r.eventid as __EventId,
    e.title as \'$f{'Title'}\',
    e.subtitle as \'$f{'Subtitle'}\',
    e.duration as \'$f{'Duration'}\',
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

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@{$term})
      or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $erg = $sth->fetchall_arrayref();
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $record  = shift || return con_err($console,gettext("No recording defined for deletion! Please use rdelete 'id'."));
    my $answer  = shift || 0;

    my @rcs  = split(/_/, $record);
    my @todelete;
    my @md5delete;
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
    
    my $sql = sprintf("SELECT SQL_CACHE  r.RecordId,CONCAT_WS('~',e.title,e.subtitle),r.RecordMD5 FROM RECORDS as r,OLDEPG as e WHERE e.eventid = r.eventid and r.RecordMD5 IN (%s) ORDER BY r.RecordId desc", join(',' => ('?') x @recordings)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@recordings)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $data = $sth->fetchall_arrayref(); # Query as array to hold ordering !

    foreach my $recording (@$data) {
        # Make hash for better reading
        my $r = {
          Id       => $recording->[0],
          Title    => $recording->[1],
          MD5      => $recording->[2]
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
        push(@md5delete,$r->{MD5}); # Remember hash

        # Delete recordings from request, if found in database
        my $i = 0;
        for my $x (@recordings) {
          if ( $x eq $recording->[2] ) { # Remove known MD5 from user request
            splice @recordings, $i, 1;
          } else {
          $i++;
          }
        }
    }
    
    con_err($console,
      sprintf(gettext("Recording '%s' does not exist in the database!"), 
      join('\',\'',@recordings))) 
          if(scalar @recordings);

    if($obj->{svdrp}->queue_cmds('COUNT')) {

        my $msg = sprintf(gettext("Recording '%s' to delete"),join('\',\'',@todelete));

        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos

        my $waiter;
        if($obj->{svdrp}->err) {
          con_err($console,$erg);
        } else {

          if(ref $console && $console->typ eq 'HTML' && !$obj->{inotify}) {
            $waiter = $console->wait($msg,0,1000,'no');
          }else {
            con_msg($console,$msg);
          }

          my $dsql = sprintf("DELETE FROM RECORDS WHERE RecordMD5 IN (%s)", join(',' => ('?') x @md5delete)); 
          my $dsth = $obj->{dbh}->prepare($dsql);
            $sth->execute(@md5delete)
              or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));

        }

        $obj->readData($watcher,$console,$waiter)
          unless($obj->{inotify});

        if(ref $console && $console->typ eq 'HTML') {
          my @t = split('~', $todelete[0]);
          if(scalar @t > 1) { # Remove subtitle
            delete $t[-1];
            $console->redirect({url => sprintf('?cmd=rlist&data=%s',url(join('~',@t))), wait => 1});
          } else {
            $console->redirect({url => '?cmd=rlist', wait => 1});
          }
        }
    } else {
        con_err($console,gettext("No recording to delete!"));
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recordid  = shift || return con_err($console,gettext("No recording defined for editing!"));
    my $data    = shift || 0;

    my $rec;
    if($recordid) {
        my $sql = qq|
SELECT SQL_CACHE 
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
        if(!$sth->execute($recordid)
          || !($rec = $sth->fetchrow_hashref())) {
          return con_err($console,sprintf(gettext("Recording '%s' does not exist in the database!"),$recordid));
        }
    }

    my $status = $obj->readinfo($rec->{Path});

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
            msg     => sprintf(gettext('Lifetime (%d ... %d)'),0,99),
            def     => int($rec->{Lifetime}),
            check   => sub{
                my $value = shift || 0;
                if($value >= 0 and $value < 100) {
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
            req     => gettext("This is required!"),
         },
        'priority' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Priority (%d ... %d)'),0,99),
            def     => int($rec->{Prio}),
            check   => sub{
                my $value = shift || 0;
                if($value >= 0 and $value < 100) {
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
            req     => gettext("This is required!"),
        },
    		'channel' => {
            typ     => 'list',
            def     => $mod->ChannelToPos($status->{channel}),
            choices => sub {
                my $erg = $mod->ChannelArray('Name');
                unshift(@$erg, [gettext("Undefined"),undef]);                          
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
        'description' => {
            msg   => gettext("Description"),
            def   => $status->{description} || '',
        },
    		'video' => {
            msg   => gettext('Video'),
            def   => $status->{video},
        },
    		'audio' => {
            msg   => gettext('Audio'),
            def   => $status->{audio},
        },
        'marks' => {
            param => {type => 'text'},
            msg   => gettext("Cut marks"),
            def   => $marks || '',
        },
    ];

    $data = $console->question(gettext("Edit recording"), $questions, $data);

    if(ref $data eq 'HASH') {
        my $dropEPGEntry = 0;
        my $ChangeRecordingData = 0;


	      $data->{title} =~s#~+#~#g;
	      $data->{title} =~s#^~##g;
        $data->{title} =~s#~$##g;

        if($data->{title} ne $rec->{title}
          or $data->{description} ne $status->{description} 
          or $data->{channel} ne $status->{channel} 
          or $data->{video} ne $status->{video}
          or $data->{audio} ne $status->{audio}) {

            my $info;
            foreach my $h (keys %{$data}) { $info->{$h} = $data->{$h}; }
            my @t = split('~', $info->{title});
            if(scalar @t > 1) { # Splitt genre~title | subtitle
                $info->{subtitle} = delete $t[-1];
                $info->{title} = join('~',@t);
            }

            $obj->saveinfo($rec->{Path},$info)
               or return con_err($console,sprintf(gettext("Couldn't write file '%s' : %s"),$rec->{Path} . '/info.vdr',$!));

            $dropEPGEntry = 1;
        }

        if($data->{marks} ne $marks) {
            save_file($marksfile, $data->{marks})
               or return con_err($console,sprintf(gettext("Couldn't write file '%s' : %s"),$marksfile,$!));
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
                 or return con_err($console,sprintf(gettext("Recording: '%s', couldn't move to '%s' : %s"),$rec->{title},$newPath,$!));

            $rec->{Path} = $newPath;
            $ChangeRecordingData = 1;
        }

        if($data->{title} ne $rec->{title}) {

            # Rename auf der Platte
            my $newPath = sprintf('%s/%s/%s', $obj->{videodir}, $obj->translate($data->{title}),basename($rec->{Path}));

            my $parentnew = dirname($newPath);
            unless( -d $parentnew) {
                mkpath($parentnew)
                    or return con_err($console,sprintf(gettext("Recording: '%s', couldn't mkpath: '%s' : %s"),$rec->{title},$parentnew,$!));
            }

            move($rec->{Path},$newPath)
                    or return con_err($console,sprintf(gettext("Recording: '%s', couldn't move to '%s' : %s"),$rec->{title},$data->{title},$!));

            my $parentold = dirname($rec->{Path});
            if($obj->{videodir} ne $parentold
                and -d $parentold
                and is_empty_dir($parentold)) {
                rmdir($parentold)
                    or return con_err($console,sprintf(gettext("Recording: '%s', couldn't remove '%s' : %s"),$rec->{title},$parentold,$!));
            }

            $ChangeRecordingData = 1;
            $dropEPGEntry = 1;
            $rec->{Path} = $newPath;
        }

        if($dropEPGEntry || $ChangeRecordingData) { 
            touch($obj->{videodir}."/.update");
        }

        if($dropEPGEntry) { # Delete EpgOld Entrys
            my $sth = $obj->{dbh}->prepare('DELETE FROM OLDEPG WHERE eventid = ?');
            $sth->execute($rec->{EventId})
                or return con_err($console,sprintf("Couldn't execute query: %s.",$sth->errstr));
        }

        if($ChangeRecordingData) { 
            my $sth = $obj->{dbh}->prepare('DELETE FROM RECORDS WHERE RecordMD5 = ?');
            $sth->execute($recordid)
                or return con_err($console,sprintf("Couldn't execute query: %s.",$sth->errstr));
        }

        if($dropEPGEntry || $ChangeRecordingData) {
          my $waiter;

          if(ref $console && $console->typ eq 'HTML' && !($obj->{inotify})) {
            $waiter = $console->wait(gettext('Recording edited!'),0,1000,'no');
          }else {
            con_msg($console,gettext('Recording edited!'));
          }
          sleep(1);
  
          $obj->readData($watcher,$console,$waiter)
            unless($obj->{inotify});

        } else {
          con_msg($console,gettext("Recording was'nt changed!"));
        }
 
        $console->redirect({url => sprintf('?cmd=rdisplay&data=%s',md5_hex($rec->{Path})), wait => 1})
            if(ref $console and $console->typ eq 'HTML');
    }

    return 1;
}

# ------------------
# Load Reccmds's
sub _loadreccmds {
# ------------------
    my $obj = shift || return error('No object defined!');

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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || 0;

    $obj->_loadreccmds;

    unless(scalar @{$obj->{reccmds}}) {
        con_err($console,gettext('No reccmds.conf on your system!'));
        return 1;
    }

    unless($data) {
        con_err($console,gettext("Please use rconvert 'cmdid_rid'"));
        unshift(@{$obj->{reccmds}}, ['Descr.', 'Command']);
        $console->table($obj->{reccmds});
        $obj->list($watcher, $console);
    }

    my ($cmdid, $recid) = split(/[\s_]/, $data);
    my $cmd = (split(':', $obj->{reccmds}->[$cmdid-1]))[-1] || return con_err($console,gettext("Couldn't find this command ID!"));
    my $path = $obj->IdToPath($recid) || return con_err($console,sprintf(gettext("Recording '%s' does not exist in the database!"),$recid));

    my $command = sprintf("%s %s",$cmd,qquote($path));
    debug sprintf('Call command %s%s',
        $command,
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );

    my $output;
    if(open P, $command .' |') { # Kommando ausführen und stdout einlesen
      @$output = <P>;
      close P;
      if( $? >> 8 > 0) {
          unshift(@$output,sprintf(gettext("Call %s '%s', standard error output :"), $cmd, $path));
          $console->message($output);
      } else {
          unshift(@$output,sprintf(gettext("Call %s '%s', standard output :"), $cmd, $path));
          $console->message($output);
      }
    } else {
          con_err($console,sprintf(gettext("Sorry! Couldn't call %s '%s'! %s"), $cmd, $path, $!));
    }

    $console->link({
        text => gettext("Back to recording list"),
        url => "?cmd=rlist",
    }) if($console->typ eq 'HTML');
    return 1;
}

# ------------------
sub status {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift;

    my $sql = qq|
SELECT SQL_CACHE 
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
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
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
    my $obj = shift || return error('No object defined!');
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  Path from RECORDS where RecordMD5 = ?');
    $sth->execute($id)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Path} : undef;
}

# ------------------
sub getPreviewFiles {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $md5 = shift || return error('No eventid defined!');

    # look for pictures
    my $outdir = sprintf('%s/%s_shot', $obj->{previewimages}, $md5);
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
    my $obj = shift || return error('No object defined!');
    my $recid = shift || return error ('No recording defined!');
    
    my $epgid = getDataById($recid, 'RECORDS', 'RecordMD5');
    if(!$epgid) {
      error sprintf("Couldn't find recording '%s'!", $recid);
      return;
    }
    my $epgdata = main::getModule('EPG')->getId($epgid->{eventid});

    my  $text    = $epgdata->{title};

    my $deep = 1;
    my $folder = scalar (my @a = split('/',$obj->{videodir})) + 1;

    my $where  = "e.eventid = r.eventid";
    if($text) {
        $deep   = scalar (my @c = split('~',$text));
        $folder += $deep;
        $deep += 1;

        $text =~ s/\'/\\\'/sg;
        $text =~ s/%/\\%/sg;
        $where  .= qq|
AND (
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text'
      OR
      SUBSTRING_INDEX(CONCAT_WS('~',e.title,e.subtitle), '~', $deep) LIKE '$text~%'
)
|;

    }

    my $sql = qq|
SELECT SQL_CACHE 
    r.RecordMD5
FROM
    RECORDS as r,
    OLDEPG as e
WHERE
    $where 
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
    my $obj = shift || return error('No object defined!');
    my $title = shift || return error ('No title in translate!');
    my $vfat = shift || $obj->{vfat};

    if($vfat eq 'y')
    {
        $title =~ s/([^üäößa-z0-9\&\!\-\s\.\@\~\,\(\)\%\+])/sprintf('#%X', ord($1))/seig;
        $title =~ s/[^üäößa-z0-9\!\&\-\#\.\@\~\,\(\)\%\+]/_/sig;
        # Windows couldn't handle '.' at the end of directory names
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
    my $obj = shift || return error('No object defined!');
    my $path = shift || return error ('Missing path from recording!' );

    my $f = sprintf("%s/index.vdr", $path);
    my $r = sprintf("%s/001.vdr", $path);

    # Pseudo Recording (DIR)
    return 0 if(! -r $f and ! -s $r);

    if(-r $f) {
        my $bytes = stat($f)->size;
        return int(($bytes / 8) / $obj->{framerate});
    } else {
        error sprintf("Couldn't read : '%s'", $f);
    }
    return 0;
}

# ------------------
# Size of recording in MB,
# return value as integer 
sub _recordingsize {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $path = shift || return error('Missing path from recording!');
    my $size = shift || 0; # Filesize offset e.g. from index.vdr

    my @files = glob("$path/[0-9][0-9][0-9].vdr");
    return $obj->_recordingCapacity(\@files,$size);
}

# ------------------
# Size of recording in MB,
# return value as integer 
sub _recordingCapacity {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $files = shift || return error('Missing files from recording!');
    my $size = shift || 0; # Filesize offset e.g. from index.vdr

    # Calc used disc space (MB)
    my $sizeMB;
    my $mb = (1024 * 1024);
    my $FileSize = 0; 

    # Incl. length of each xxx.vdr
    foreach my $f (@{$files}) {
      if($size > $mb) {
        $sizeMB = int($size / $mb);
        $size -= $sizeMB * $mb;
        $FileSize += $sizeMB;
      }
      $size += stat($f)->size;
    }
    if($size > 0) {
      $sizeMB = int($size / $mb);
      $FileSize += $sizeMB;
    }

    return $FileSize;
}

# ------------------
sub converttitle {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $title = shift || return error ('No title in translate!');
    my $vfat = shift || $obj->{vfat};

    $title =~ s/_/ /g;

    if($vfat eq 'y') {
        $title =~ s/\#([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $title =~ s/\x03/:/g; # See backward compat.. at recordings.c
    }

    $title =~ s/\x01/\'/g;
    $title =~ s/\x02/\\/g;

    $title =~ s/\//~/g;

    return $title;
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
        my $sql = qq|
    SELECT SQL_CACHE 
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
    SELECT SQL_CACHE 
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
            or return error "Couldn't execute query: $sth->errstr.";
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}

# ------------------
sub recover {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $recordid  = shift || 0;
    my $data    = shift || 0;

    my $files; # Array with md5 and humanreadable title
    my $paths; # Hash with md5 and path to recording
    find(
            {
                wanted => sub{
                    if(-r $File::Find::name) {
                        if($File::Find::name =~ /\.del\/\d{3}.vdr$/sig) {  # Lookup for *.del/001.vdr
                          my $path = dirname($File::Find::name);
                          my $md5 = md5_hex($path);
                          unless(exists $paths->{$md5}) {
                            my $title = dirname($path);
                            $title =~ s/^$obj->{videodir}//g;
                            $title =~ s/^\///g;
                            push(@{$files},[$obj->converttitle($title),$md5]);
                            $paths->{$md5} = $path;
                          }
                        }
                    } else {
                        lg "Permissions deny, couldn't read : $File::Find::name";
                    }
                },
                follow => 1,
                follow_skip => 2,
            },
        $obj->{videodir}
    );

    return con_msg($console,gettext("There none recoverable recordings!"))
      unless($files and scalar @{$files});

    my $questions = [
      'restore' => {
        msg     => gettext('Title of recording'),
        req     => gettext("This is required!"),
        typ     => 'list',
        options => 'multi',
        def   => sub {
            my @ret;
            foreach my $v (@{$files}) {
              push(@ret,$v->[1]);
            }
            return @ret;
          },
        choices => $files,
        check   => sub{
            my $value = shift || return undef, gettext("This is required!");
            my @ret = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
            return join(',', @ret);
          }
      },
    ];

    $data = $console->question(gettext("Recover recording"), $questions, $data);
    if(ref $data eq 'HASH') {
        my $ChangeRecordingData = 0;

        foreach my $md5 (split(/\s*,\s*/, $data->{restore})) {
          unless(exists $paths->{$md5}) {
            con_err($console,gettext("Can't recover recording, maybe was this in the meantime deleted!"));
            next;
          }

          my $path = $paths->{$md5};
          my $newPath = $path;
          $newPath =~ s/\.del$/\.rec/g;
          lg sprintf("Recover recording, rename '%s' to %s",$path,$newPath);
          if(!move($path,$newPath)) {
            con_err($console,sprintf(gettext("Recover recording, couldn't rename '%s' to %s : %s"),$path,$newPath,$!));
            next;
          }
          $ChangeRecordingData = 1;
        }

        if($ChangeRecordingData) {
          my $waiter;

          touch($obj->{videodir}."/.update");

          if(ref $console && $console->typ eq 'HTML' && !($obj->{inotify})) {
            $waiter = $console->wait(gettext('Recording recovered!'),0,1000,'no');
          }else {
            con_msg($console,gettext('Recording recovered!'));
          }
          sleep(1);
  
          $obj->readData($watcher,$console,$waiter)
            unless($obj->{inotify});

        } else {
          con_msg($console,gettext("None recording was'nt recovered!"));
        }
 
        $console->redirect({url => '?cmd=rlist', wait => 1})
            if(ref $console and $console->typ eq 'HTML');
    }

    return 1;
}

1;
