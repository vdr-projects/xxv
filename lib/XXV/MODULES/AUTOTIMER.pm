package XXV::MODULES::AUTOTIMER;

use strict;

use Tools;
use Locale::gettext;
use POSIX ":sys_wait_h", qw(strftime);

# ------------------
# Name:  module
# Descr: The standard routine to describe the Plugin
# Usage: my $modhash = $obj->module();
# ------------------
sub module {
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'AUTOTIMER',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module searches for EPG entries with user-defined text and creates new timers.'),
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
            exclude => {
                description => gettext('Exclude channels from autotimer'),
                type        => 'string',
                default     => 'POS > 50',
                check   => sub{
                    my $value = shift;
                    if(index($value, ',') != -1) {
                        return 'POS > 50'; # Nur um sicher zu sein, das die alten Werte nicht übernommen werden.
                    } else {
                        return $value;
                    }
                },
            },
        },
        Commands => {
            astatus => {
                description => gettext('Display status of autotimers.'),
                short       => 'as',
                callback    => sub{ $obj->status(@_) },
                DenyClass   => 'alist',
            },
            anew => {
                description => gettext("Create new autotimer"),
                short       => 'an',
                callback    => sub{ $obj->autotimerCreate(@_) },
                Level       => 'user',
                DenyClass   => 'aedit',
            },
            adelete => {
                description => gettext("Delete a autotimer 'aid'"),
                short       => 'ad',
                callback    => sub{ $obj->autotimerDelete(@_) },
                Level       => 'user',
                DenyClass   => 'aedit',
            },
            aedit => {
                description => gettext("Edit an autotimer 'aid'"),
                short       => 'ae',
                callback    => sub{ $obj->autotimerEdit(@_) },
                Level       => 'user',
                DenyClass   => 'aedit',
            },
            asearch => {
                description => gettext("Search for autotimer with text 'aid'"),
                short       => 'ase',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'alist',
            },
            alist => {
                description => gettext("Show autotimer 'aid'"),
                short       => 'al',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'alist',
            },
            aupdate => {
                description => gettext("Start autotimer search."),
                short       => 'au',
                callback    => sub{ $obj->autotimer(@_) },
                Level       => 'user',
                DenyClass   => 'aedit',
            },
            atoggle => {
                description => gettext("Toggle autotimer on or off 'aid'"),
                short       => 'at',
                callback    => sub{ $obj->autotimerToggle(@_) },
                Level       => 'user',
                DenyClass   => 'aedit',
            },
            asuggest => {
                hidden      => 'yes',
                callback    => sub{ $obj->suggest(@_) },
                DenyClass   => 'alist',
            },
        },
        RegEvent    => {
            'newTimerfromAutotimer' => {
                Descr => gettext('Create event entries if an autotimer has created a new timer.'),

                # You have this choices (harmless is default):
                # 'harmless', 'interesting', 'veryinteresting', 'important', 'veryimportant'
                Level => 'veryinteresting',

                # Search for a spezial Event.
                # I.e.: Search for an LogEvent with match
                # "Sub=>text" = subroutine =~ /text/
                # "Msg=>text" = logmessage =~ /text/
                # "Mod=>text" = modname =~ /text/
                SearchForEvent => {
                    Sub => 'AUTOTIMER',
                    Msg => 'Save timer',
                },
                # Search for a Match and extract the information
                # of the TimerId
                # ...
                Match => {
                    TimerId => qr/TimerId\:\s+\"(\d+)\"/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});
                            my $autotimer = getDataById($timer->{AutotimerId}, 'AUTOTIMER', 'Id');
                            my $title = sprintf(gettext("Autotimer('%s') found: %s"),
                                                    $autotimer->{Search}, $timer->{File});
                            my $description = sprintf(gettext("On: %s to %s\nDescription: %s"),
                                $timer->{NextStartTime},
                                fmttime($timer->{Stop}),
                                $desc && $desc->{description} ? $desc->{description} : ''
                                );

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, "interesting");
                        }
                    |,
                ],

            },
        },
    };
    return $args;
}

# ------------------
# Name:  status
# Descr: Standardsubroutine to report statistical data for Report Plugin.
# Usage: my $report = $obj->status([$watcher, $console]);
# ------------------
sub status {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift || 0;

    my $sql = qq|
SELECT SQL_CACHE 
    t.Id as __Id,
    t.File,
    t.Status as __Status,
    c.Name as Channel,
    c.Pos as __Pos,
    DATE_FORMAT(t.Day, '%e.%c.%Y') as Day,
    t.Start,
    t.Stop,
    t.Priority,
    UNIX_TIMESTAMP(t.NextStartTime) as __Day,
    t.Collision as __Collision,
    t.eventid as __NextEpgId,
    t.AutotimerId as __AutotimerId
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.ChannelID = c.Id
    and UNIX_TIMESTAMP(t.addtime) > ?
    and t.AutotimerId > 0
ORDER BY
    t.NextStartTime|;

    my $fields = fields($obj->{dbh}, $sql);
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($lastReportTime)
        or return error "Couldn't execute query: $sth->errstr.";
    my $erg = $sth->fetchall_arrayref();
    for(@$erg) {
        $_->[6] = fmttime($_->[6]);
        $_->[7] = fmttime($_->[7]);
    }

    unshift(@$erg, $fields);
    return {
        message => sprintf(gettext('Autotimer has programmed %d new timer(s) since last report to %s'),
            (scalar @$erg - 1), scalar localtime($lastReportTime)),
        table   => $erg,
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

    # file
    $self->{file} = $self->{config}->{file};

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize module');

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

    my $version = main::getDBVersion();
    # don't remove old table, if updated rows => warn only
    if(!tableUpdated($obj->{dbh},'AUTOTIMER',$version,0)) {
      return 0;
    }

    # Look for table or create this table
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS AUTOTIMER (
          Id int(11) unsigned auto_increment NOT NULL,
          Activ enum('y', 'n') default 'y',
          Done set('timer', 'recording', 'chronicle' ) NOT NULL default 'timer', 
          Search text NOT NULL default '',
          InFields set('title', 'subtitle', 'description' ) NOT NULL,
          Channels text default '',
          Start char(4) default '0000',
          Stop  char(4) default '0000',
          MinLength tinyint default NULL,
          Priority tinyint(2) default NULL,
          Lifetime tinyint(2) default NULL,
          Dir text,
          VPS enum('y', 'n') default 'n',
          prevminutes tinyint default NULL,
          afterminutes tinyint default NULL,
          Weekdays set('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'),
          startdate datetime default NULL,
          stopdate datetime default NULL,
          count int(11) default NULL,
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    main::after(sub{
        my $m = main::getModule('EPG');
        $m->updated(sub{
          return 0 if($obj->{active} ne 'y');

          lg 'Start autotimer callback to find new events!';
          return $obj->autotimer();

        });
        return 1;
    }, "AUTOTIMER: Install callback at update epg data ...", 30);

    return 1;
}

# ------------------
# Name:  autotimer
# Descr: Routine to parse the EPG Data for users Autotimer.
#        If Autotimerid given, then will this search only
#        for this Autotimer else for all.
# Usage: $obj->autotimer([$autotimerid]);
# ------------------
sub autotimer {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $autotimerid = shift;

    # Get Autotimer
    my $sth;
    if($autotimerid) {
        $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  * from AUTOTIMER where Activ = "y" AND Id = ? order by Id');
        $sth->execute($autotimerid)
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    } else {
        $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE  * from AUTOTIMER where Activ = "y" order by Id');
        $sth->execute()
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    }
    my $att = $sth->fetchall_hashref('Id');

    my $waiter;
    if(ref $console && !$autotimerid && $console->typ eq 'HTML') {
        my $zaehler = scalar keys %$att;
        $waiter = $console->wait(gettext("Searching for autotimer ..."), 0, ++$zaehler, 'no');
    }

    my $l = 0; # Lines for Waiter
    my $C = 0; # Total of created and modifed timers
    my $M = 0;
    my $log;

    my $vdrVersion = main::getVdrVersion();

    # Search only for event there added since last runtime.
    # and search not with TEMPEPG at manual running
    my $addtime = ((not ref $console) && ($obj->{addtime})) ? $obj->{addtime} : 0;
    $obj->{addtime} = time unless($autotimerid);

    &bench('AUTOTIMER');
    if($addtime) {

      # Remove old data
      $obj->{dbh}->do('DELETE FROM TEMPEPG');

      # Copy only new events from EPG to TEMPEPG, to speed up search
      my $sql = qq|INSERT INTO TEMPEPG SELECT e.* FROM EPG as e, CHANNELS as c
                   WHERE e.addtime >= FROM_UNIXTIME(?)|;

      # Exclude unwanted channels
      if($obj->{exclude}) {
          $sql .= sprintf(' AND ( e.channel_id = c.Id ) AND NOT (c.%s)', 
                  $obj->{exclude});
      }

      my $sth = $obj->{dbh}->prepare($sql)
        or return error sprintf("Couldn't prepare query: %s.",$sql);
      $sth->execute($addtime)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    }

    # Get Timersmodule
    my $timermod = main::getModule('TIMERS');
    foreach my $id (sort keys %$att) {
        my $a = $att->{$id};

        $waiter->next(++$l, undef, sprintf(gettext("Search for autotimer with ID(%d) with search pattern '%s'"), $id, $a->{Search}))
          if(ref $waiter);

        if(ref $console && $autotimerid) {
            $console->message(' ') if($console->{TYP} eq 'HTML');
            $console->message(sprintf(gettext("Search for autotimer with ID(%d) with search pattern '%s'"), $id, $a->{Search}));
        }

        # Build SQL Command and run it ....
        my $events = $obj->_eventsearch($a, $timermod, $addtime ) || next;

        # Only search for one at?
        if(ref $console && $autotimerid) {
            $console->message(sprintf(gettext("Found %d entries for '%s' in EPG database."), scalar keys %$events, $a->{Search}));
            foreach my $Id (sort keys %$events) {
              my $output = [
                  [gettext("Title")	     , $events->{$Id}->{Title}],
                  [gettext("Subtitle")	 , $events->{$Id}->{Subtitle}],
                  [gettext("Channel")	   , $events->{$Id}->{Channel}],
                  [gettext("Start")	     , strftime("%x %X", localtime($events->{$Id}->{starttime}))],
                  [gettext("Stop")	     , strftime("%x %X", localtime($events->{$Id}->{stoptime}))],
                  [gettext("Description"), $events->{$Id}->{Summary}],
              ];
              $console->table($output);
            };
        }

        # Every found and save this as timer
        my $c = 0;
        my $m = 0;
        foreach my $Id (sort keys %$events) {
            $events->{$Id}->{Activ} = 'y';
            $events->{$Id}->{VPS} = '';
            $events->{$Id}->{Priority} = $a->{Priority};
            $events->{$Id}->{Lifetime} = $a->{Lifetime};

            $events->{$Id}->{File} = $obj->_placeholder($events->{$Id}, $a);

            if($events->{$Id}->{vpsstart} and $a->{VPS}) {
              $events->{$Id}->{VPS} = 'y';
 	            $events->{$Id}->{starttime} = $events->{$Id}->{vpsstart};
 	            $events->{$Id}->{stoptime} = $events->{$Id}->{vpsstop};
            }

            # Add anchor for reidentify timer
            my $aidcomment = sprintf('#~AT[%d]', $id);

        		if($vdrVersion >= 10344){
          	        $events->{$Id}->{Summary} = $aidcomment;
        		} else {
                    $events->{$Id}->{Summary} .= $aidcomment;
        		}
            
            # Wished timer already exist with same data from autotimer ?
            next if($obj->_timerexists($events->{$Id}, $aidcomment));

            # Adjust timers set by the autotimer
            my $timerID = $obj->_timerexistsfuzzy($events->{$Id}, $aidcomment);

            if(!$timerID && $a->{Done}) {

                my @done = split(',', $a->{Done});

                # Ignore timer if it already with same title recorded
                if(grep(/^chronicle$/, @done) && $obj->_chronicleexists($events->{$Id}, $aidcomment)) {
                  lg sprintf("Don't create timer from AT(%d) '%s', because found same data on chronicle", $id, $events->{$Id}->{File});
                  next;
                }

                # Ignore timer if it already with same title recorded
                if(grep(/^recording$/, @done) && $obj->_recordexists($events->{$Id}, $aidcomment)){
                  lg sprintf("Don't create timer from AT(%d) '%s', because found same data on recordings", $id, $events->{$Id}->{File});
                  next;
                }
                # Ignore timer if it already a timer with same title programmed, on other place
                if(grep(/^timer$/, @done) && $obj->_timerexiststitle($events->{$Id}, $aidcomment)){
                  lg sprintf("Don't create timer from AT(%d) '%s', because found same data on other timers", $id, $events->{$Id}->{File});
                  next;
                }
            }

            my $error = 0;

            my ($bsec,$bmin,$bhour,$bmday,$bmon,$byear,$bwday,$byday,$bisdst) = localtime($events->{$Id}->{starttime});
            my ($esec,$emin,$ehour,$emday,$emon,$eyear,$ewday,$eyday,$eisdst) = localtime($events->{$Id}->{stoptime});

            if($timermod->{newTimerFormat}) {
              $events->{$Id}->{Day} = sprintf("%04d-%02d-%02d",$byear+1900,$bmon+1,$bmday);
            } else {
              $events->{$Id}->{Day} = sprintf("%02d",$bmday);
            }
            $events->{$Id}->{Start} = sprintf("%02d%02d",$bhour,$bmin);
            $events->{$Id}->{Stop}  = sprintf("%02d%02d",$ehour,$emin);

            my $erg = $timermod->saveTimer($events->{$Id}, $timerID ? $timerID : undef);
            foreach my $zeile (@$erg) {
                if($zeile =~ /^(\d{3})\s+(.+)/) {
                    $error = $2 if(int($1) >= 500);
                }
            }
            if($error) {
                $console->err(sprintf(gettext("Could not save timer for '%s' : %s"), $events->{$Id}->{File}, $error))
                    if(ref $console && $autotimerid);
            } else {
                if($timerID) {
                    ++$m;
                        $console->message(sprintf(gettext("Modified timer for '%s'."), $events->{$Id}->{File}))
                            if(ref $console && $autotimerid);
                } else {
                    ++$c;
                        $console->message(sprintf(gettext("Timer for '%s' has been created."), $events->{$Id}->{File}))
                            if(ref $console && $autotimerid);
                }
            }
        }
        $C += $c;
        $M += $m;
        if($c) {
            my $msg = sprintf(gettext("Created %d timer for '%s'."), $c, $a->{Search});
            if(ref $console && $autotimerid) {
                $console->message($msg);
            }
            else {
                push(@{$log},$msg);
            }
        }
        if($m) {
            my $msg = sprintf(gettext("Modified %d timer for '%s'."), $m, $a->{Search});
            if(ref $console && $autotimerid) {
                $console->message($msg);
            }
            else {
                push(@{$log},$msg);
            }
        }
    }

    &bench('AUTOTIMER');
    my $seconds = &bench()->{'AUTOTIMER'};
    lg sprintf("Runtime %s seconds", $seconds);
    

    $waiter->next(undef,undef,gettext('Read new timers into database.'))
      if(ref $waiter);

    sleep 1;

    $timermod->readData();

    # last call of waiter
    $waiter->end() if(ref $waiter);

    if(ref $console) {
        $console->start() if(ref $waiter);
        unshift(@{$log},sprintf(gettext("Autotimer process created %d timers and modified %d timers."), $C, $M));
        lg join("\n", @$log);
        $console->message($log);
        $console->link({
            text => gettext("Back to autotimer listing."),
            url => "?cmd=alist",
        }) if($console->typ eq 'HTML');
    }

    return 1;
}

# ------------------
# Name:  autotimerCreate
# Descr: Routine to display the create form for Autotimer.
# Usage: $obj->autotimerCreate($watcher, $console, [$userdata]);
# ------------------
sub autotimerCreate {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || 0;
    my $data    = shift || 0;

    $obj->autotimerEdit($watcher, $console, $timerid, $data);
}

# ------------------
# Name:  autotimerEdit
# Descr: Routine to display the edit form for Autotimer.
# Usage: $obj->autotimerEdit($watcher, $console, [$atid], [$userdata]);
# ------------------
sub autotimerEdit {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || 0;
    my $data    = shift || 0;

    my $mod = main::getModule('CHANNELS');
    my $modT = main::getModule('TIMERS');

    my $epg;
    if($timerid and not ref $data) {
        my $sth = $obj->{dbh}->prepare("SELECT SQL_CACHE  * from AUTOTIMER where Id = ?");
        $sth->execute($timerid)
            or return $console->err(sprintf(gettext("The autotimer '%s' does not exist in the database."),$timerid));
        $epg = $sth->fetchrow_hashref();

            # Channels Ids in Namen umwandeln
            if($epg->{Channels}) {
              my @channels = map { $_ = $mod->ChannelToPos($_) } split(/[\s|,]+/, $epg->{Channels});
              $epg->{Channels} = \@channels;
            }

            # question erwartet ein Array
            my @done = split(/\s*,\s*/, $epg->{Done});
            $epg->{Done} = \@done;
            my @infields = split(/\s*,\s*/, $epg->{InFields});
            $epg->{InFields} = \@infields;
            my @weekdays = split(/\s*,\s*/, $epg->{Weekdays});
            $epg->{Weekdays} = \@weekdays;

    } elsif (ref $data eq 'HASH') {
        $epg = $data;
    }

    my %wd = (
        'Mon' => gettext('Mon'),
        'Tue' => gettext('Tue'),
        'Wed' => gettext('Wed'),
        'Thu' => gettext('Thu'),
        'Fri' => gettext('Fri'),
        'Sat' => gettext('Sat'),
        'Sun' => gettext('Sun')
    );

    my %in = (
        'title' => gettext('Title'),
        'subtitle' => gettext('Subtitle'),
        'description' => gettext('Description')
    );

    my %do = (
        'timer' => gettext('Timer'),
        'recording' => gettext('Existing recording'),
        'chronicle' => gettext('Recording chronicle')
    );
    my $DoneChoices = [$do{'timer'}, $do{'recording'}];

    # Enable option "chronicle" only if activated.
    my $cm  = main::getModule('CHRONICLE');
    push(@$DoneChoices, $do{'chronicle'})
      if($cm and $cm->{active} eq 'y');

    my $questions = [
        'Id' => {
            typ     => 'hidden',
            def     => $epg->{Id} || 0,
        },
        'Activ' => {
            typ     => 'confirm',
            def     => $epg->{Activ} || 'y',
            msg     => gettext('Activate this autotimer'),
        },
        'Search' => {
            msg   => 
gettext("Search terms to search for EPG entries.
You can also fine tune your search :
* by adding 'operators' to your search terms such as 'AND', 'OR', 'AND NOT' e.g. 'today AND NOT tomorrow'
* by comma-separated search terms e.g. 'today,tomorrow'
* by a hyphen to exclude search terms e.g. 'today,-tomorrow'"),
            def   => $epg->{Search} || '',
        },
        'InFields' => {
            msg   => gettext('Search in this EPG fields'),
            typ   => 'checkbox',
            choices   => [$in{'title'}, $in{'subtitle'}, $in{'description'}],
            req   => gettext('This is required!'),
            def   => sub {
                            my $value = $epg->{InFields} || ['title','subtitle'];
                            my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                            my @ret;
                            foreach my $v (@vals) {
                                push(@ret,$in{$v});
                            }
                            return @ret;
                          },
            check   => sub{
                my $value = shift || return;
                my $data = shift || return error('No Data in CB');
                my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                my @ret;
                foreach my $v (@vals) {
                    unless(grep($_ eq $v, @{$data->{choices}})) {
                        my $ch = join(' ', @{$data->{choices}});
                        return undef, sprintf(gettext("You can choose: %s!"),$ch);
                    }
                    foreach my $k (keys %in) {
                        push(@ret,$k)
                            if($v eq $in{$k});
                    }
                }
                return join(',', @ret);
            },
        },
        'Channels' => {
            typ     => 'list',
            def     => $epg->{Channels},
            choices => $mod->ChannelArray('Name', sprintf(' NOT (%s)', $obj->{exclude})),
            options => 'multi',
            msg     => gettext('Limit search to these channels'),
            check   => sub{
                my $value = shift || return;
                my @vals;
                foreach my $chname ((ref $value eq 'ARRAY' ? @$value : split(/\s*,\s*/, $value))) {
                    if( my $chid = $mod->PosToChannel($chname) || $mod->NameToChannel($chname)) {
                        push(@vals, $chid);
                    } else {
                        return undef, sprintf(gettext("The channel '%s' does not exist!"),$chname);
                    }
                }
                return join(',', @vals);
            },
        },
        'Done' => {
            msg   => gettext('Ignore retries with same title?'),
            typ   => 'checkbox',
            choices   => $DoneChoices,
            def   => sub {
                            my $value = $epg->{Done};
                            my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                            my @ret;
                            foreach my $v (@vals) {
                                push(@ret,$do{$v});
                            }
                            return @ret;
                          },
            check   => sub{
                my $value = shift || '';
                my $data = shift || return error('No Data in CB');
                my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                my @ret;
                foreach my $v (@vals) {
                    unless(grep($_ eq $v, @{$data->{choices}})) {
                        my $ch = join(' ', @{$data->{choices}});
                        return undef, sprintf(gettext("You can choose: %s!"),$ch);
                    }
                    foreach my $k (keys %do) {
                        push(@ret,$k)
                            if($v eq $do{$k});
                    }
                }
                return join(',', @ret);
            },
        },
         'Start' => {
             typ     => 'string',
             def     => sub{
		             my $value = $epg->{Start} || return "";
                     return fmttime($value);
                 },
             msg     => gettext("Start time in format 'HH:MM'"),
             check   => sub{
                 my $value = shift || 0;
                 return undef, gettext('You set a start time without an end time!')
                    if(not $data->{Stop} and $value);
        		 return "" if(not $value);
        		 $value = fmttime($value) if($value =~ /^\d+$/sig);
                 return undef, gettext('The time is incorrect!') if($value !~ /^\d+:\d+$/sig);
                 my @v = split(':', $value);
                 $value = sprintf('%02d%02d',$v[0],$v[1]);
                 if(int($value) < 2400 and int($value) >= 0) {
                     return sprintf('%04d',$value);
                 } else {
                     return undef, gettext('The time is incorrect!');
                 }
             },
         },
         'Stop' => {
             typ     => 'string',
             def     => sub{
    		         my $value = $epg->{Stop} || return "";
                     return fmttime($value);
                 },
             msg     => gettext("End time in format 'HH:MM'"),
             check   => sub{
                 my $value = shift || 0;
                 return undef, gettext('You set an end time without a start time!')
                    if(not $data->{Start} and $value);
        		 return "" if(not $value);
        		 $value = fmttime($value) if($value =~ /^\d+$/sig);
                 return undef, gettext('The time is incorrect!') if($value !~ /^\d+:\d+$/sig);
                 my @v = split(':', $value);
                 $value = sprintf('%02d%02d',$v[0],$v[1]);
                 if(int($value) < 2400 and int($value) >= 0) {
                     return sprintf('%04d',$value);
                 } else {
                     return undef, gettext('The time is incorrect!');
                 }
             },
        },
        'Weekdays' => {
            msg   => gettext('Only search these weekdays'),
            typ   => 'checkbox',
            choices   =>  [$wd{'Mon'}, $wd{'Tue'}, $wd{'Wed'}, $wd{'Thu'}, $wd{'Fri'}, $wd{'Sat'}, $wd{'Sun'}],
            def   => sub {
                            my $value = $epg->{Weekdays} || ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                            my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                            my @ret;
                            foreach my $v (@vals) {
                                push(@ret,$wd{$v});
                            }
                            return @ret;
                          },
            check   => sub{
                my $value = shift || [$wd{'Mon'}, $wd{'Tue'}, $wd{'Wed'}, $wd{'Thu'}, $wd{'Fri'}, $wd{'Sat'}, $wd{'Sun'}];
                my $data = shift || return error('No Data in CB');
                my @vals = (ref $value eq 'ARRAY') ? @$value : split(/\s*,\s*/, $value);
                my @ret;
                foreach my $v (@vals) {
                    unless(grep($_ eq $v, @{$data->{choices}})) {
                        my $ch = join(' ', @{$data->{choices}});
                        return undef, sprintf(gettext("You can choose: %s!"),$ch);
                    }
                    foreach my $k (keys %wd) {
                        push(@ret,$k)
                            if($v eq $wd{$k});
                    }
                }
                return join(',', @ret);
            },
        },
        'VPS' => {
            typ     => 'confirm',
            def     => $epg->{VPS} || 'n',
            msg     => gettext('Activate VPS for new timers'),
        },
        'prevminutes' => {
            typ     => 'integer',
            msg     => gettext('Buffer time in minutes before the scheduled start of a recording'),
            def     => $epg->{prevminutes},
            check   => sub{
                my $value = shift;
                return if($value eq "");
                if($value =~ /^\d+$/sig and $value >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'afterminutes' => {
            typ     => 'integer',
            msg     => gettext('Buffer time in minutes past the scheduled end of a recording'),
            def     => $epg->{afterminutes},
            check   => sub{
                my $value = shift;
                return if($value eq "");
                if($value =~ /^\d+$/sig and $value >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'MinLength' => {
            typ     => 'integer',
            msg     => gettext('Minimum play time in minutes'),
            def     => $epg->{MinLength} || 0,
            check   => sub{
                my $value = shift || return;
                if($value =~ /^\d+$/sig and $value > 0) {
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'Priority' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Priority (%d ... %d)'),0,$console->{USER}->{MaxPriority} ? $console->{USER}->{MaxPriority} : 99 ),
            def     => (defined $epg->{Priority} ? $epg->{Priority} : $modT->{Priority}),
            check   => sub{
                my $value = shift || 0;
                if($value =~ /^\d+$/sig and $value >= 0 and $value < 100) {
                    if($console->{USER}->{MaxPriority} and $value > $console->{USER}->{MaxPriority}) {
                        return undef, sprintf(gettext('Sorry, but the maximum priority is limited to %d!'), $console->{USER}->{MaxPriority});
                    }
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'Lifetime' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Lifetime (%d ... %d)'),0,$console->{USER}->{MaxLifeTime} ? $console->{USER}->{MaxLifeTime} : 99 ),
            def     => (defined $epg->{Lifetime} ? $epg->{Lifetime} : $modT->{Lifetime}),
            check   => sub{
                my $value = shift || 0;
                if($value =~ /^\d+$/sig and $value >= 0 and $value < 100) {
                    if($console->{USER}->{MaxLifeTime} and $value > $console->{USER}->{MaxLifeTime}) {
                        return undef, sprintf(gettext('Sorry, but the maximum life time is limited to %d!'), $console->{USER}->{MaxLifeTime});
                    }
                    return int($value);
                } else {
                    return undef, gettext('Value incorrect!');
                }
            },
        },
        'Dir' => {
						typ 		=> 'string',
            msg     => gettext('Group all recordings into one directory'),
            def     => $epg->{Dir},
            # choices   =>  main::getModule('TIMERS')->getRootDirs,
        },
    ];

    # Ask Questions
    $data = $console->question(($timerid ? gettext('Edit autotimer')
					 : gettext('Create new autotimer')), $questions, $data);

    if(ref $data eq 'HASH') {
        delete $data->{Channel};

    	$obj->_insert($data);

    	$data->{Id} = $obj->{dbh}->selectrow_arrayref('SELECT SQL_CACHE  max(ID) FROM AUTOTIMER')->[0]
    		if(not $data->{Id});

        $console->message(gettext('Autotimer saved!'));
        debug sprintf('%s autotimer with search "%s" is saved%s',
            ($timerid ? 'Changed' : 'New'),
            $data->{Search},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );
        $obj->autotimer($watcher, $console, $data->{Id});
    }
    return 1;
}

# ------------------
# Name:  autotimerDelete
# Descr: Routine to display the delete form for Autotimer.
# Usage: $obj->autotimerDelete($watcher, $console, $atid);
# ------------------
sub autotimerDelete {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || return $console->err(gettext("No autotimer defined for deletion! Please use adelete 'aid'!"));   # If timerid the edittimer

    my @timers  = reverse sort{ $a <=> $b } split(/[^0-9]/, $timerid);

    my $sql = sprintf('DELETE FROM AUTOTIMER where Id in (%s)', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    if(!$sth->execute(@timers)) {
        error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $console->err(sprintf gettext("The autotimer '%s' does not exist in the database."), join(',', @timers));
        return 0;
    }

    $console->message(sprintf gettext("Autotimer %s deleted."), join(',', @timers));
    debug sprintf('autotimer with id "%s" is deleted%s',
        join(',', @timers),
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );
    $console->redirect({url => '?cmd=alist', wait => 1})
        if($console->typ eq 'HTML');
}

# ------------------
# Name:  autotimerToogle
# Descr: Switch the Autotimer on or off.
# Usage: $obj->autotimerToogle($watcher, $console, $atid);
# ------------------
sub autotimerToggle {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || return $console->err(gettext("No autotimer defined to toggle! Please use atoggle 'aid'!"));

    my @timers  = reverse sort{ $a <=> $b } split(/[^0-9]/, $timerid);

    my $sql = sprintf('SELECT SQL_CACHE  Id,Activ FROM AUTOTIMER where Id in (%s)', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    if(!$sth->execute(@timers)) {
        error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $console->err(sprintf(gettext("The autotimer '%s' does not exist in the database."),$timerid));
        return 0;
    }
    my $data = $sth->fetchall_hashref('Id');

    my $erg;
    for my $timer (@timers) {

        unless(exists $data->{$timer}) {
            $console->err(sprintf(gettext("The autotimer '%s' does not exist in the database."), $timer));
            next;
        }

        my $status = (($data->{$timer}->{Activ} eq 'n' ) ? 'y' : 'n');

        my $sql = "UPDATE AUTOTIMER set Activ = ? where Id = ?"; 
        my $sth = $obj->{dbh}->prepare($sql);
        if(!$sth->execute($status,$timer)) {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
            $console->err(sprintf(gettext("Couldn't toggle autotimer with ID '%s'!"),$timer));
            next;
        }

        debug sprintf('Autotimer with id "%s" is %s%s',
            $timer,
            ($status eq 'n' ? 'disabled' : 'activated'),
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        if($console->typ ne 'AJAX') {
            my $text = ($status eq 'n') ? gettext('disabled')
                                        : gettext('activated');
            $console->message(sprintf gettext("Autotimer %s is %s."), $timer, $text);
        }

        # AJAX 
        push(@$erg,[$timer,($status eq 'n' ? 0 : 1),0,0]);
    }

    $console->redirect({url => '?cmd=alist', wait => 1})
        if($console->typ eq 'HTML');

    if($console->typ eq 'AJAX') {
      # { "data" : [ [ ID, ON, RUN, CONFLICT ], .... ] }
      # { "data" : [ [ 5, 1, 0, 0 ], .... ] }
      $console->table($erg);
    }

}

# ------------------
# Name:  list
# Descr: List Autotimers in a table display.
# Usage: $obj->list($watcher, $console, [$atid], [$params]);
# ------------------
sub list {
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text      = shift || '';
    my $params  = shift;

	  my $term;
	  my $search = '';
	  if($text and $text =~ /^[0-9,_ ]+$/ ) {
      my @timers  = split(/[^0-9]/, $text);
      $search = sprintf(" WHERE Id in (%s)",join(',' => ('?') x @timers));
      foreach(@timers) { push(@{$term},$_); }

	  } elsif($text) {
      my $query = buildsearch("Search,Dir",$text);
      $search = sprintf('WHERE %s', $query->{query});
      foreach(@{$query->{term}}) { push(@{$term},$_); }
	  }

    my %f = (
        'Id' => gettext('Service'),
        'Activ' => gettext('Activ'),
        'Search' => gettext('Search'),
        'Channels' => gettext('Channels'),
        'Start' => gettext('Start'),
        'Stop' => gettext('Stop'),
        'Dir' => gettext('Directory'),
        'Min' => gettext('Minimum length'),
    );

    my $sql = qq|
    SELECT SQL_CACHE 
      Id as \'$f{'Id'}\',
      Activ as \'$f{'Activ'}\',
      Search as \'$f{'Search'}\',
      Channels as \'$f{'Channels'}\',
      Dir as \'$f{'Dir'}\',
      Start as \'$f{'Start'}\',
      Stop as \'$f{'Stop'}\',
      MinLength as \'$f{'Min'}\'
    FROM
      AUTOTIMER
    $search
    |;

    my $fields = fields($obj->{dbh}, $sql);

    my $sortby = gettext("Search");
    $sortby = $params->{sortby}
        if(exists $params->{sortby} && grep(/^$params->{sortby}$/i,@{$fields}));
    $sql .= " order by $sortby";
    if(exists $params->{desc} && $params->{desc} == 1) {
        $sql .= " desc"; }
    else {
        $sql .= " asc"; }

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@{$term})
      or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);

    my $channels = main::getModule('CHANNELS')->ChannelHash('Id');
    my $timers = main::getModule('TIMERS')->getTimersByAutotimer();

    $console->table($erg,
        {
            sortable => 1,
            channels => $channels,
            timers => $timers,
        }
    );
}


# ------------------
sub _eventsearch {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $a   = shift  || return error('No data defined!');
    my $timermod = shift || return error('No timer modul defined!');
    my $addtime = shift;

    my $query;
    my $search = '1';
    my $term = [];
  
    if($a->{Search}) {
      $query = buildsearch($a->{InFields}, $a->{Search});
      $search = $query->{query};
      $term = $query->{term};
    }

    # Start and Stop
    if($a->{Start} and $a->{Stop}) {
        if($a->{Start} > $a->{Stop}) {
            $search .= "\n AND ((DATE_FORMAT(e.starttime, '%H%i') > ? AND DATE_FORMAT(e.starttime, '%H%i') < 2359) OR (DATE_FORMAT(e.starttime, '%H%i') >= 0 and DATE_FORMAT(e.starttime, '%H%i') < ?))";
        } else {
            $search .= "\n AND (DATE_FORMAT(e.starttime, '%H%i') > ? AND DATE_FORMAT(e.starttime, '%H%i') < ?)";
        }
        push(@{$term},$a->{Start});
        push(@{$term},$a->{Stop});    
    }

    # Min Length
    if(exists $a->{MinLength} and $a->{MinLength}) {
        $search .= " AND e.duration >= ?";
        push(@{$term},$a->{MinLength} * 60);    
    }

    # Channels
    if($a->{Channels} and my @channelids = split(',', $a->{Channels})) {
        $search .= sprintf(" AND channel_id in (%s)",join(',' => ('?') x @channelids));
        foreach(@channelids) {
          push(@{$term},$_);
        }
    }

    # Weekdays
    if($a->{Weekdays} and my @weekdays = split(',', $a->{Weekdays})) {
        if(scalar @weekdays != 7 and scalar @weekdays != 0) {
          $search .= sprintf(" AND DATE_FORMAT(e.starttime, \'%%a\') in (%s)",join(',' => ('?') x @weekdays));
          foreach(@weekdays) {
            push(@{$term},$_);
          }
        }
    }

    # Exclude channels, ifn't already lookup for channels
    if($obj->{exclude} && not $a->{Channels} && not $addtime) {
        $search .= sprintf(' AND NOT (c.%s)', $obj->{exclude});
    }

	# Custom time range
	my $after = 0;
	my $prev = 0;
#	if($a->{VPS} ne 'y') {
	  if(defined $a->{prevminutes}) {
			$prev = $a->{prevminutes} * 60;
		} else {
			$prev = $timermod->{prevminutes} * 60;
		}
		if(defined $a->{afterminutes}) {
			$after = $a->{afterminutes} * 60;
		} else {
			$after = $timermod->{afterminutes} * 60;
		}
#	}

    my $table = $addtime ? 'TEMPEPG' : 'EPG';

    # Search for events
    my $sql = qq|
SELECT SQL_CACHE 
    e.eventid as eventid,
    e.channel_id as ChannelID,
    c.Name as Channel,
    c.POS as POS,
    e.title as Title,
    e.subtitle as Subtitle,
    e.description as Summary,
    (UNIX_TIMESTAMP(e.starttime) - ? ) as starttime,
    (UNIX_TIMESTAMP(e.starttime) + e.duration + ?) as stoptime,
    UNIX_TIMESTAMP(e.vpstime) as vpsstart,
    (UNIX_TIMESTAMP(e.vpstime) + e.duration) as vpsstop
FROM
    $table as e,
    CHANNELS as c
WHERE
    ( $search )
    AND ( e.channel_id = c.Id )|;

#dumper $sql;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($prev,$after,@{$term})
      or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    return $sth->fetchall_hashref('eventid');
}

# ------------------
sub _timerexists {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eventdata = shift  || return error('No data defined!');
    my $aidcomment = shift || return error('No data defined!');

    # Avoid Timer already defined (the timer with the same data again do not put on)
    my $sql = "SELECT SQL_CACHE  count(*) as cc from TIMERS where
                ChannelID = ?
                and UNIX_TIMESTAMP(NextStartTime) = ?
                and UNIX_TIMESTAMP(NextStopTime)  = ?
                and Priority = ?
                and Lifetime = ?
                and (
                       ( Status & 1 = '0' )
                    or ( File = ? and Summary = ? )
                    or ( Summary not like ? )
                )";

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventdata->{ChannelID},$eventdata->{starttime},$eventdata->{stoptime},
                  $eventdata->{Priority},$eventdata->{Lifetime},
                  $eventdata->{File},$eventdata->{Summary},"%".$aidcomment)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg->{cc} 
        if($erg);
    return 0;

}

# ------------------
sub _timerexistsfuzzy {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eventdata = shift  || return error('No data defined!');
    my $aidcomment = shift || return error('No data defined!');

    # Adjust timers set by the autotimer
    my $timerID = 0;
    my $sql = "SELECT SQL_CACHE  ID from TIMERS where
                ChannelID = ?
                and UNIX_TIMESTAMP(NextStartTime) = ?
                and UNIX_TIMESTAMP(NextStopTime)  = ?
                and Summary like ?
                order by length(Summary) desc;";

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventdata->{ChannelID},$eventdata->{starttime},$eventdata->{stoptime},
                  "%".$aidcomment)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg->{ID} 
        if($erg);
    return 0;
}

# ------------------
sub _recordexists {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eventdata = shift  || return error('No data defined!');
    my $aidcomment = shift || return error('No data defined!');

    # Ignore timer if it already with same title recorded
    my $sql = "SELECT SQL_CACHE  count(*) as cc
                FROM RECORDS as r, OLDEPG as e
                WHERE e.eventid = r.EventId
                    AND CONCAT_WS('~',e.title,IF(e.subtitle<>'',e.subtitle,NULL)) = ?";

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventdata->{File})
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg->{cc} 
        if($erg);
    return 0;
}

# ------------------
sub _chronicleexists {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eventdata = shift  || return error('No data defined!');
    my $aidcomment = shift || return error('No data defined!');

    my $chroniclemod  = main::getModule('CHRONICLE');
    return 0
      unless($chroniclemod and $chroniclemod->{active} eq 'y');

    my $sql = "SELECT SQL_CACHE  count(*) as cc from CHRONICLE where title = ?";
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventdata->{File})
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg->{cc} 
        if($erg);
    return 0;
}

# ------------------
sub _timerexiststitle {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $eventdata = shift  || return error('No data defined!');
    my $aidcomment = shift || return error('No data defined!');

    my $sql = "SELECT SQL_CACHE  count(*) as cc from TIMERS where File = ?";

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($eventdata->{File})
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg->{cc} 
        if($erg);
    return 0;
}


# ------------------
sub _insert {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $data = shift || return;

    if(ref $data eq 'HASH') {
        my ($names, $vals, $kenn);
        map {
            push(@$names, $_);
            push(@$vals, $data->{$_}),
            push(@$kenn, '?'),
        } sort keys %$data;

        my $sql = sprintf("REPLACE INTO AUTOTIMER (%s) VALUES (%s)",
                join(', ', @$names),
                join(', ', @$kenn),
        );
        my $sth = $obj->{dbh}->prepare( $sql );
        $sth->execute( @$vals );
    } else {
        my $sth = $obj->{dbh}->prepare('REPLACE INTO AUTOTIMER VALUES (?,?,?,?,?,?,?,?,?)');
        $sth->execute( @$data );
    }
}

# ------------------
# Name:  _placeholder
# Descr: Replace the placeholder with extendet EPG
# Usage: my $text = $obj->_placeholder($epgdata, $autotimerdata);
# ------------------
sub _placeholder {
    my $obj  = shift  || return error('No object defined!');
    my $data = shift  || return error('No data defined!');
    my $at   = shift  || return error('No attribute defined!');

    my $file;

    if ($at->{Dir}) {
    	my $title = $at->{Dir};
        if($title =~ /.*%.*%.*/sig) {
	 	   my %at_details;
                $at_details{'title'}            = $data->{Title};
                $at_details{'subtitle'}         = $data->{Subtitle} ? $data->{Subtitle} : $data->{Start};
                $at_details{'date'}             = $data->{Day};
                $at_details{'regie'}            = $1 if $data->{Summary} =~ m/\|Director: (.*?)\|/;
                $at_details{'category'}         = $1 if $data->{Summary} =~ m/\|Category: (.*?)\|/;
                $at_details{'genre'}            = $1 if $data->{Summary} =~ m/\|Genre: (.*?)\|/;
                $at_details{'year'}             = $1 if $data->{Summary} =~ m/\|Year: (.*?)\|/;
                $at_details{'country'}          = $1 if $data->{Summary} =~ m/\|Country: (.*?)\|/;
                $at_details{'originaltitle'}    = $1 if $data->{Summary} =~ m/\|Originaltitle: (.*?)\|/;
                $at_details{'fsk'}              = $1 if $data->{Summary} =~ m/\|FSK: (.*?)\|/;
                $at_details{'episode'}          = $1 if $data->{Summary} =~ m/\|Episode: (.*?)\|/;
                $at_details{'rating'}           = $1 if $data->{Summary} =~ m/\|Rating: (.*?)\|/;
                $title =~ s/%([\w_-]+)%/$at_details{lc($1)}/sieg;
				$file = $title;
        } else { # Classic mode DIR~TITLE~SUBTILE
          if($data->{Subtitle}) {
            $file = sprintf('%s~%s~%s', $at->{Dir}, $data->{Title},$data->{Subtitle});
          } else {
            $file = sprintf('%s~%s', $at->{Dir}, $data->{Title});
          }
        }
	  } elsif($data->{Subtitle}) {
		  $file = sprintf('%s~%s', $data->{Title},$data->{Subtitle});
    } else {
		  $file = $data->{Title};
    }

    # sind irgendweche Tags verwendet worden, die leer waren und die doppelte Verzeichnisse erzeugten?
    $file =~s#~+#~#g;
    $file =~s#^~##g;
    $file =~s#~$##g;

    return $file;
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
        Search
    FROM
        AUTOTIMER
    WHERE
    	( Search LIKE ? )
    GROUP BY
        Search
    ORDER BY
        Search
    LIMIT 25
        |;
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute('%'.$search.'%')
            or return error "Couldn't execute query: $sth->errstr.";
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}

1;
