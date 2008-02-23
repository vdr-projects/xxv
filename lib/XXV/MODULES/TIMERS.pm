package XXV::MODULES::TIMERS;

use strict;
use Tools;
use POSIX ":sys_wait_h", qw(strftime mktime);
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'TIMERS',
        Prereq => {
            'Date::Manip' => 'date manipulation routines',
        },
        Description => gettext('This module reads timers and saves it to the database.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $obj->status(@_) },
        Preferences => {
            interval => {
                description => gettext('How often timers are to be updated (in seconds)'),
                default     => 30 * 60,
                type        => 'integer',
                required    => gettext("This is required!"),
            },
            prevminutes => {
                description => gettext('Buffer time in minutes before the scheduled start of a recording'),
                default     => 5,
                type        => 'integer',
            },
            afterminutes => {
                description => gettext('Buffer time in minutes past the scheduled end of a recording'),
                default     => 5,
                type        => 'integer',
            },
            Priority => {
                description => gettext('Priority of a timer for recordings when creating a new timer'),
                default     => 50,
                type        => 'integer',
            },
            Lifetime => {
                description => gettext('The guaranteed lifetime (in days) of a recording created by this timer'),
                default     => 50,
                type        => 'integer',
            },
            DVBCards => {
                description => gettext('How much DVB cards exist on this system'),
                default     => 1,
                type        => 'integer',
            },
            usevpstime => {
                description => gettext('Use Programme Delivery Control (PDC) to control start time'),
                default     => 'n',
                type        => 'confirm',
            },
            adjust => {
                description => gettext('Change timers if EPG entries change'),
                default     => 'y',
                type        => 'confirm',
            },
        },
        Commands => {
            tlist => {
                description => gettext("List timers 'tid'"),
                short       => 'tl',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'tlist',
            },
            tsearch => {
                description => gettext("Search timers 'text'"),
                short       => 'ts',
                callback    => sub{ $obj->list(@_) },
                DenyClass   => 'tlist',
            },
            tupdate => {
                description => gettext("Read timers and write them to the database"),
                short       => 'tu',
                callback    => sub{ $obj->readData(@_)},
                Level       => 'user',
                DenyClass   => 'tedit',
            },
            tnew => {
                description => gettext("Create timer 'eid'"),
                short       => 'tn',
                callback    => sub{ $obj->newTimer(@_) },
                Level       => 'user',
                DenyClass   => 'tedit',
            },
            tedit => {
                description => gettext("Edit timer 'tid'"),
                short       => 'te',
                callback    => sub{ $obj->editTimer(@_) },
                Level       => 'user',
                DenyClass   => 'tedit',
            },
            tdelete => {
                description => gettext("Delete timer 'tid'"),
                short       => 'td',
                callback    => sub{ $obj->deleteTimer(@_) },
                Level       => 'user',
                DenyClass   => 'tedit',
            },
            ttoggle => {
                description => gettext("Activate/Deactive timer 'tid'"),
                short       => 'tt',
                callback    => sub{ $obj->toggleTimer(@_) },
                Level       => 'user',
                DenyClass   => 'tedit',
            },
            tsuggest => {
                hidden      => 'yes',
                callback    => sub{ $obj->suggest(@_) },
                DenyClass   => 'tlist',
            },
        },
        RegEvent    => {
            'newTimerfromUser' => {
                Descr => gettext('Create event entries if the user has created a new timer.'),

                # You have this choices (harmless is default):
                # 'harmless', 'interesting', 'veryinteresting', 'important', 'veryimportant'
                Level => 'interesting',

                # Search for a spezial Event.
                # I.e.: Search for an LogEvent with match
                # "Sub=>text" = subroutine =~ /text/
                # "Msg=>text" = logmessage =~ /text/
                # "Mod=>text" = modname =~ /text/
                SearchForEvent => {
                    Msg => 'New timer',
                },
                # Search for a Match and extract the information
                # of the id
                # ...
                Match => {
                    TimerId => qr/id\:\s+\"(\d+)\"/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            return if($timer->{autotimerid});
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});
                            my $title = sprintf(gettext("New timer found: %s"),$timer->{file});

                            my $description = '';                           

                            my $channel = main::getModule('CHANNELS')->ChannelToName($timer->{channel});
                            $description .= sprintf(gettext("Channel: %s"), $channel);
                            $description .= "\r\n";

                            Date_Init("Language=English");
                            my $d = ParseDate($timer->{starttime});
                            $timer->{starttime} = datum(UnixDate($d,"%s")) if($d);
  
                            $description .= sprintf(gettext("On: %s to %s"),
                                $timer->{starttime},
                                fmttime($timer->{stop}));
                            $description .= "\r\n";
                            $description .= sprintf(gettext("Description: %s"), $desc->{description} )
                              if($desc && $desc->{description});

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            my $soap = main::getModule('SHARE');
                            my $level = 1;
                            if($timer->{autotimerid}) {
                                $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 2 : 3);
                            } else {
                                $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 4 : 5);
                            }

                            if($timer->{eventid}) {
                                my $event = main::getModule('EPG')->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                            }
                        }|,
                ],

            },
            'deleteTimer' => {
                Descr => gettext('Create event entries if the user has deleted a timer.'),
                Level => 'interesting',
                SearchForEvent => {
                    Msg => 'delt',
                },
                Match => {
                    TimerId => qr/delt\s+(\d+)/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            my $title = sprintf(gettext("Timer deleted: %s"),$timer->{file});
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});

                            my $description = '';                           

                            my $channel = main::getModule('CHANNELS')->ChannelToName($timer->{channel});
                            $description .= sprintf(gettext("Channel: %s"), $channel);
                            $description .= "\r\n";

                            Date_Init("Language=English");
                            my $d = ParseDate($timer->{starttime});
                            $timer->{starttime} = datum(UnixDate($d,"%s")) if($d);

                            $description .= sprintf(gettext("On: %s to %s"),
                                $timer->{starttime},
                                fmttime($timer->{stop}));
                            $description .= "\r\n";
                            $description .= sprintf(gettext("Description: %s"), $desc->{description} )
                              if($desc && $desc->{description});

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            my $soap = main::getModule('SHARE');
                            my $level = 1;

                            if($timer->{eventid}) {
                                my $event = main::getModule('EPG')->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                            }
                        }|,
                ],
            },
            'toggleTimer' => {
                Descr => gettext('Create event entries if the user has toggled a timer.'),
                Level => 'interesting',
                SearchForEvent => {
                    Msg => 'modt',
                },
                Match => {
                    TimerId => qr/modt\s+(\d+)\s(on|off)/s,
                    Type    => qr/modt\s+\d+\s+(on|off)/s
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            my $title;
                            if($args->{Type} eq 'on') {
                              $title = sprintf(gettext("Timer activated: %s"),$timer->{file});
                            } else {
                              $title = sprintf(gettext("Timer deactivated: %s"),$timer->{file});
                            }

                            my $description = '';                           

                            my $channel = main::getModule('CHANNELS')->ChannelToName($timer->{channel});
                            $description .= sprintf(gettext("Channel: %s"), $channel);
                            $description .= "\r\n";

                            Date_Init("Language=English");
                            my $d = ParseDate($timer->{starttime});
                            $timer->{starttime} = datum(UnixDate($d,"%s")) if($d);
  
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});
                            $description .= sprintf(gettext("On: %s to %s"),
                                $timer->{starttime},
                                fmttime($timer->{stop}));
                            $description .= "\r\n";
                            $description .= sprintf(gettext("Description: %s"), $desc->{description} )
                              if($desc && $desc->{description});

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'pos');
                            my $soap = main::getModule('SHARE');
                            my $level = ($args->{Type} eq 'off' ? 1 : 2);
                            if($timer->{autotimerid} and $args->{Type} eq 'on') {
                                $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 2 : 3);
                            } elsif($args->{Type} eq 'on') {
                                $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 4 : 5);
                            }

                            if($timer->{eventid}) {
                                my $event = main::getModule('EPG')->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                            }
                        }|,
                ],
            },
            'updateTimer' => {
                Descr => gettext('Create event entries if a timer has been updated.'),
                Level => 'harmless',
                SearchForEvent => {
                    Msg => 'Reread',
                },
                Match => {
                    HighId => qr/Reread\s+(\d+)\s+timers/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $modS = main::getModule('SHARE') or return;
                            my $modE = main::getModule('EPG') or return;
                            for (my $i = 1; $i<=$args->{HighId}; $i++) {
                                my $timer  = getDataById($i, 'TIMERS', 'pos');

                                my $level = 1;
                                if($timer->{autotimerid} and ($timer->{flags} & 1)) {
                                    $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 2 : 3);
                                } elsif($timer->{flags} & 1) {
                                    $level = (($timer->{priority} <= 50 or $timer->{lifetime} < 33) ? 4 : 5);
                                }

                                if($timer->{eventid}) {
                                    my $event = $modE->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                    $modS->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                                }
                            }
                    }|,
                ],
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
    {
        my $sth = $obj->{dbh}->prepare("SELECT SQL_CACHE  count(*) as count from TIMERS");
        if(!$sth->execute())
        {
            error sprintf("Couldn't execute query: %s.",$sth->errstr);
        } else {
            my $erg = $sth->fetchrow_hashref();
            $total = $erg->{count} if($erg && $erg->{count});
        }
    }

    return {
        message => sprintf(gettext('%d timer exists.'), $total),
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

    my $version = 28; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows
    if(!tableUpdated($obj->{dbh},'TIMERS',$version,1)) {
        return 0;
    }

    # Look for table or create this table
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS TIMERS (
          id varchar(32) NOT NULL,
          pos int(11) unsigned NOT NULL,
          flags char(1) default 1,
          channel varchar(100) NOT NULL default '',
          day varchar(20) default '-------',
          start int(11) unsigned,
          stop int(11) unsigned,
          priority tinyint(2),
          lifetime tinyint(2),
          file text,
          aux text default '',
          starttime datetime,
          stoptime datetime,
          collision varchar(100) default '0',
          eventid int unsigned default '0',
          eventstarttime datetime,
          eventduration int unsigned default '0',
          autotimerid int(11) unsigned default '0',
          checked char(1) default 0,
          addtime timestamp,
          PRIMARY KEY(id)
        ) COMMENT = '$version'
    |);

    $obj->{after_updated} = [];

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Couldn't get modul SVDRP");
           return 0;
        }

        $obj->_readData();

        # Interval to read timers and put to DB
        Event->timer(
          interval => $obj->{interval},
          prio => 6,  # -1 very hard ... 6 very low
          cb => sub{
            $obj->_readData();
          }
        );
        return 1;
    }, "TIMERS: Store timers in database ...", 10);


    return 1;
}

# ------------------
sub saveTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $data = shift || return error('No data defined!');

    $obj->_saveTimer($data);
    if($obj->{svdrp}->queue_cmds('COUNT')) {
      my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos

      # Save shortly this timer in DB if this only a new timer (at)
      # Very Important for Autotimer!
      my $pos = $1 if($erg->[1] =~ /^250\s+(\d+)/);
      if(!(exists $data->{pos}) and $pos) {
          $data->{pos} = $pos;
          $obj->_insert($data);
      }

      event sprintf('Save timer "%s" with id: "%d"', $data->{file}, $pos || 0);

      $obj->{changedTimer} = 1;

      return $erg;
  }
  return 0;
}

# ------------------
sub _saveTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $data = shift || return error('No data defined!');

    $data->{flags}  = ($data->{activ} eq 'y' ? 1 : 0);
    $data->{flags} |= ($data->{vps} eq 'y' ? 4 : 0);

    $data->{file} =~ s/(\r|\n)//sg;
    $data->{aux}  =~ s/(\r|\n)//sg if(exists $data->{aux});

    my $file = $data->{file};
    $file =~ s/:/|/g;

    $obj->{svdrp}->queue_cmds(
        sprintf("%s %s:%s:%s:%s:%s:%s:%s:%s:%s",
            $data->{pos} ? "modt $data->{pos}" : "newt",
            $data->{flags},
            $data->{channel},
            $data->{day},
            $data->{start},
            $data->{stop},
            int($data->{priority}),
            int($data->{lifetime}),
            $file,
            ($data->{aux} || '')
        )
    );
}

sub _newTimerdefaults {
    my $obj     = shift || return error('No object defined!');
    my $timer     = shift;

    $timer->{activ} = 'y';
    $timer->{priority} = $obj->{Priority};
    $timer->{lifetime} = $obj->{Lifetime};

    if($timer->{vpsstart} && $obj->{usevpstime} eq 'y') {
      $timer->{vps} = 'y';
      $timer->{day} = $timer->{vpsday};
      $timer->{start} = $timer->{vpsstart};
      $timer->{stop} = $timer->{vpsstop};
    } else {
      $timer->{vps} = 'n';
    }
}
# ------------------
sub newTimer {
# ------------------
    my $obj     = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $epgid   = shift || 0;
    my $epg     = shift || 0;

    my $fast = (ref $epg and exists $epg->{fast}) ? 1 : 0;
    if($epgid and ( (not ref $epg) || $fast) ) {
      my @events  = reverse sort{ $a <=> $b } split(/[^0-9]/, $epgid);
      my $sql = qq|
SELECT SQL_CACHE 
    eventid,
    channel_id as channel,
    description,
    CONCAT_WS('~', title, subtitle) as file,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) - ? ), '%Y-%m-%d') as day,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) - ? ), '%H%i') as start,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) + duration + ? ), '%H%i') as stop,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(vpstime)), '%Y-%m-%d') as vpsday,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(vpstime)), '%H%i') as vpsstart,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(vpstime) + duration), '%H%i') as vpsstop
FROM
    EPG
WHERE|;
    $sql .= sprintf(" eventid in (%s)", join(',' => ('?') x @events));

      my $data;
      my $sth = $obj->{dbh}->prepare($sql);
      if(!$sth->execute($obj->{prevminutes} * 60, $obj->{prevminutes} * 60, $obj->{afterminutes} * 60, @events)
        || !($data = $sth->fetchall_hashref('eventid'))
        || (scalar keys %{$data} < 1)) {
          return $console->err(sprintf(gettext("Event '%s' does not exist in the database!"),join(',',@events)));
      }

      my $count = 1;
      foreach my $eventid (keys %{$data}) {
        $epg = $data->{$eventid};
        $obj->_newTimerdefaults($epg);
        $epg->{action} = 'save' if(scalar keys %{$data} > 1 || $fast );
        $obj->_editTimer($watcher, $console, 0, $epg) if($count < scalar keys %{$data});
        $count += 1;
      }
    }
    if(not ref $epg) {
		  my $t = time;
 	    $epg = {
            channel   => '',
            file      => gettext('New timer'),
            day       => my_strftime("%Y-%m-%d",$t),
            start     => my_strftime("%H%M",$t),
            stop      => my_strftime("%H%M",$t)
    	};
      $obj->_newTimerdefaults($epg);
    }
    $obj->editTimer($watcher, $console, 0, $epg);
}

# ------------------
sub _editTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || 0;   # If timerid the edittimer
    my $data    = shift || 0;  # Data for defaults

    my $timerData;
    if($timerid and not ref $data) {
        my $sth = $obj->{dbh}->prepare(
qq|
SELECT SQL_CACHE 
    id, 
    channel, 
    file, 
    aux, 
    start, 
    stop, 
    day, 
    priority, 
    lifetime, 
    IF(flags & 1,'y','n') as activ,
    IF(flags & 4,'y','n') as vps,
    (SELECT description
      FROM EPG as e
      WHERE t.eventid = e.eventid
      LIMIT 1) as description
FROM
    TIMERS as t
WHERE
    id = ?
|);

      if(!$sth->execute($timerid)
        || !($timerData = $sth->fetchrow_hashref())
        || (scalar keys %{$timerData} < 1)) {
          return $console->err(sprintf(gettext("Timer '%s' does not exist in the database!"),$timerid));
      }
    } elsif (ref $data eq 'HASH') {
        $timerData = $data;
    }

    $timerData->{aux} =~ s/(\r|\n)//sig
        if(defined $timerData->{aux});

    my $modC = main::getModule('CHANNELS');
    my $con = $console->typ eq "CONSOLE";

    my $questions = [
        'id' => {
            typ     => 'hidden',
            def     => $timerData->{id} || 0,
        },
        'activ' => {
            typ     => 'confirm',
            def     => $timerData->{activ},
            msg     => gettext('Enable this timer'),
        },
        'vps' => {
            typ     => 'confirm',
            def     => $timerData->{vps},
            msg     => gettext('Use PDC time to control timer'),
        },
        'file' => {
            msg     => gettext('Title of recording'),
            def     => $timerData->{file},
            req     => gettext("This is required!"),
        },
        'channel' => {
            typ     => 'list',
            def     => $con ? $modC->ChannelToPos($timerData->{channel}) : $timerData->{channel},
            choices => $con ? $modC->ChannelArray('Name') : $modC->ChannelWithGroup('Name,Id'),
            msg     => gettext('Which channel should recorded'),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift;
                return undef, gettext("This is required!")
                  unless($value);

                my $ch = $modC->ToCID($value);
                return undef, sprintf(gettext("This channel '%s' does not exist!"),$value)
                  unless($ch);
                return $ch;                
            },
        },
        'day' => {
            typ     => $con ? 'string' : 'date',
            def     => sub{
                # Convert day from VDR format to locale format
                my $value = $timerData->{day};
                if($value and $value =~ /^\d{4}\-\d{2}-\d{2}$/) {
                  Date_Init("Language=English");
                  my $d = ParseDate($value);
                  if($d) {
                    my $t = UnixDate($d,gettext("%Y-%m-%d"));
                    return $t if($t);
                  }
                }
                return $value;
            },
            msg     => gettext("Enter a day (1 to 31) or weekday in format 'MTWTFSS'."),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift || return;
                # Convert locale format to VDR format %Y-%m-%d
                if($value and $value !~ /^\d+$/ and $value =~ /^\d+/) {
                  Date_Init(split(',',gettext("Language=English")));
                  my $d = ParseDate($value);
                  if($d) {
                    my $t = UnixDate($d,'%Y-%m-%d');
                    return $t if($t);
                  }
                }
                if(($value =~ /^\d+$/ and int($value) <= 31 and int($value) > 0)# 13
                        or $value =~ /^\d{4}\-\d{2}-\d{2}$/sig                  # 2005-03-13
                        or $value =~ /^\S{7}\@\d{4}\-\d{2}-\d{2}$/sig           # MTWTFSS@2005-03-13
                        or $value =~ /^\S{7}\@\d{2}$/sig                        # MTWTFSS@13
                        or $value =~ /^\S{7}$/) {                               # MTWTFSS
                    return $value;
                } else {
                    return undef, gettext('The day is incorrect or was in a wrong format!');
                }
            },
        },
        'start' => {
            typ     => 'string',
            def     => sub{
                    return fmttime($timerData->{start});
                },
            msg     => gettext("Start time in format 'HH:MM'"),
            check   => sub{
                my $value = shift;
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
        'stop' => {
            typ     => 'string',
            def     => sub{
                    return fmttime($timerData->{stop});
                },
            msg     => gettext("End time in format 'HH:MM'"),
            check   => sub{
                my $value = shift;
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
        'priority' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Priority (%d ... %d)'),0,$console->{USER}->{MaxPriority} ? $console->{USER}->{MaxPriority} : 99 ),
            def     => int($timerData->{priority}),
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
        'lifetime' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Lifetime (%d ... %d)'),0,$console->{USER}->{MaxLifeTime} ? $console->{USER}->{MaxLifeTime} : 99 ),
            def     => int($timerData->{lifetime}),
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
        'aux' => {
            typ     => 'hidden',
            def   => $timerData->{aux},
        },
        'description' => {
            msg       =>  gettext('Description'),
            typ       => $timerData->{description} ? 'string' : 'hidden',
            def       => $timerData->{description},
            readonly  => 1
        }
    ];

    # Ask Questions
    my $datasave = $console->question(($timerid ? gettext('Edit timer')
                                                : gettext('New timer')), $questions, $data);

    if(ref $datasave eq 'HASH') {
        if($timerid) {
          $datasave->{pos} = $obj->getPos($timerid);
        }
        $obj->_saveTimer($datasave);
        return 1;
    }
    return 0;
}
# ------------------
sub editTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift;   # If timerid the edittimer
    my $data    = shift;  # Data for defaults

    if($obj->_editTimer($watcher,$console,$timerid,$data) 
        && $obj->{svdrp}->queue_cmds('COUNT')) {
          my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
          my $error;
          foreach my $zeile (@$erg) {
            if($zeile =~ /^(\d{3})\s+(.+)/) {
                $error = $2 if(int($1) >= 500);
            }
          }

          unless($error) {
            debug sprintf('%s timer with title "%s" is saved%s',
                ($timerid ? 'Changed' : 'New'),
                $data->{file},
                ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
                );
                $console->message($erg);

          } else {
            error sprintf('%s timer with title "%s" does\'nt saved : %s',
                ($timerid ? 'Changed' : 'New'),
                $data->{file},
                $error
                );
                $console->err($erg);
          }
          $obj->{changedTimer} = 1;

          if($obj->_readData($watcher,$console)) {
            $console->redirect({url => '?cmd=tlist', wait => 1})
              if(!$error && $console->typ eq 'HTML');
          }
    }
}

# ------------------
sub deleteTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || return $console->err(gettext("No timer defined for deletion! Please use tdelete 'tid'."));   # If timerid the edittimer
    my $answer  = shift || 0;

    my @timers  = split(/[^0-9a-f]/, $timerid);

    my $sql = sprintf('SELECT SQL_CACHE id,pos,file,channel,starttime,flags & 1 and NOW() between starttime and stoptime FROM TIMERS where id in (%s) ORDER BY pos desc', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@timers)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_arrayref();

    my $modC = main::getModule('CHANNELS') or return;
    foreach my $d (@$data) {
        my $t = {
          id      => $d->[0],
          pos     => $d->[1],
          file    => $d->[2],
          channel => $d->[3],
          start   => $d->[4],
          running => $d->[5]
        };

        if(ref $console and $console->{TYP} eq 'CONSOLE') {
            $console->table({
              gettext('Title')   => $t->{file},
              gettext('Channel') => $modC->ChannelToName($t->{channel}),
              gettext('Start')   => $t->{start},
            });
            my $confirm = $console->confirm({
                typ   => 'confirm',
                def   => 'y',
                msg   => gettext('Would you like to delete this timer?'),
            }, $answer);
            next if(!$answer eq 'y');
        }

        debug sprintf('Delete timer with title "%s"%s',
            $t->{file},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $obj->{svdrp}->queue_cmds(sprintf("modt %d off", $t->{pos}))
          if($t->{running});
        $obj->{svdrp}->queue_cmds(sprintf("delt %d", $t->{pos}));

        # Delete timer from request, if found in database
        my $i = 0;
        for my $x (@timers) {
          if ( $x eq $t->{id} ) { # Remove known MD5 from user request
            splice @timers, $i, 1;
          } else {
            $i++;
          }
        }
    }

    con_err($console,
      sprintf(gettext("Timer '%s' does not exist in the database!"), 
      join('\',\'',@timers))) 
          if(scalar @timers);

    if($obj->{svdrp}->queue_cmds('COUNT')) {
        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
        $console->msg($erg, $obj->{svdrp}->err)
            if(ref $console);

        sleep(1);

        if($obj->_readData($watcher,$console)) {
          $console->redirect({url => '?cmd=tlist', wait => 1})
            if(ref $console and $console->typ eq 'HTML');
        }
    } else {
        $console->err(gettext("No timer to delete!"));
    }

    return 1;
}

# ------------------
sub toggleTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $timerid = shift || return $console->err(gettext("No timer defined to toggle! Please use ttoggle 'id'."));   # If timerid the edittimer

    my @timers  = split(/[^0-9a-f]/, $timerid);

    my $sql = sprintf('SELECT SQL_CACHE id,pos,file,flags,starttime,stoptime FROM TIMERS where id in (%s) ORDER BY pos desc', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@timers)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_arrayref();
    my $ref;
    my @success;

    foreach my $d (@$data) {
        my $t = {
          id      => $d->[0],
          pos     => $d->[1],
          file    => $d->[2],
          flags   => $d->[3],
          start   => $d->[4],
          stop    => $d->[5]
        };

        # Build query for all timers with possible collisions
        $ref .= " or '$t->{start}' between starttime and stoptime"
             .  " or '$t->{stop}'  between starttime and stoptime";


    	  my $status = (($t->{flags} & 1) ? 'off' : 'on');

        debug sprintf('Timer with title "%s" is %s%s',
            $t->{file},
            ($status eq 'on' ? 'activated' : 'deactivated'),
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $obj->{svdrp}->queue_cmds("modt $t->{pos} $status"); # Sammeln der Kommandos

        # Delete timer from request, if found in database
        my $i = 0;
        for my $x (@timers) {
          if ( $x eq $t->{id} ) { # Remove known MD5 from user request
            splice @timers, $i, 1;
          } else {
            $i++;
          }
        }
        push(@success,$t->{id});
    }

    con_err($console,
      sprintf(gettext("Timer '%s' does not exist in the database!"), 
      join('\',\'',@timers))) 
          if(scalar @timers);

    if($obj->{svdrp}->queue_cmds('COUNT')) {

        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
        $console->msg($erg, $obj->{svdrp}->err)
            if(ref $console and $console->typ ne 'AJAX');

        if($obj->_readData($watcher, $console)) {
          $console->redirect({url => '?cmd=tlist', wait => 1})
            if(ref $console and $console->typ eq 'HTML');
        }

        if(ref $console and $console->typ eq 'AJAX') {
          # { "data" : [ [ ID, ON, RUN, CONFLICT ], .... ] }
          # { "data" : [ [ 5, 1, 0, 0 ], .... ] }
          my $sql = sprintf('SELECT SQL_CACHE id, flags & 1 as Active, NOW() between starttime and stoptime as Running, Collision from TIMERS where id in (%s) %s',
                             join(',' => ('?') x @success),$ref); 
          my $sth = $obj->{dbh}->prepare($sql);
          $sth->execute(@success)
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
          my $erg = $sth->fetchall_arrayref();
          $console->table($erg);
        }

        return 1;
    } else {
        $console->err(gettext('No timer to toggle!'));
        return undef;
    }
}


# ------------------
sub _insert {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $timer = shift || return;
    my $checked = shift || 0;

    # import only status which used from vdr and thereby exclude eventid from vdradmin
    $timer->{flags} &= 15;

    # change pos to channelid, because change to telnet reader
    if(index($timer->{channel}, '-') < 0) {
      $timer->{channel} = main::getModule('CHANNELS')->ToCID($timer->{channel})
        or return error(sprintf("Couldn't get channel from this timer: %d '%s'", $timer->{pos}, $timer->{channel}));
    }

    $timer->{file} =~ s/\|/\:/g;

    # NextTime
    my $nexttime = $obj->getNextTime( $timer->{day}, $timer->{start}, $timer->{stop} )
        or return error(sprintf("Couldn't get time from this timer: %d '%s' '%s' '%s'", $timer->{pos}, $timer->{day}, $timer->{start}, $timer->{stop}));

    # AutotimerId
    my $atxt = (split('~', $timer->{aux}))[-1];
    my $aid = $1 if(defined $atxt and $atxt =~ /AT\[(\d+)\]/);

    # Search for event at EPG
    my $e = $obj->_getNextEpgId( {
          pos     => $timer->{pos},
          flags   => $timer->{flags},
          channel => $timer->{channel},
          file    => $timer->{file},
          start   => $nexttime->{start},
          stop    => $nexttime->{stop},
        });

    my $sth = $obj->{dbh}->prepare(
q|REPLACE INTO TIMERS VALUES 
  (MD5(CONCAT(?,?,?)),?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?), FROM_UNIXTIME(?),0,?,?,?,?,?,NOW())
|);
    $sth->execute( 
         $timer->{channel},$nexttime->{start},$nexttime->{stop},
         $timer->{pos},
         $timer->{flags},
         $timer->{channel},
         $timer->{day},
         $timer->{start},
         $timer->{stop},
         $timer->{priority},
         $timer->{lifetime},
         $timer->{file},
         $timer->{aux},
         $nexttime->{start},
         $nexttime->{stop},
         $e ? $e->{eventid} : 0,
         $e ? $e->{starttime} : 0,
         $e ? $e->{duration} : 0,
         $aid,
         $checked
     ) or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
}


# Read data
# ------------------
sub _readData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    # Search for correct times
    $obj->getCheckTimer()
      if($obj->{adjust} eq 'y');

    my $oldTimers = &getDataByTable('TIMERS');

    $obj->{dbh}->do('DELETE FROM TIMERS');

    # read from svdrp
    my $tlist = $obj->{svdrp}->command('lstt');

    my $c = 0;
    foreach my $line (@$tlist) {
        next if(! $line or $line =~ /^22/);
        $line =~ s/^\d+[- ]+\d+\s//sig;
        $c++;
        my @data = split(':', $line, 9);
        if(scalar @data > 2) {
          my $timer = {
            pos     => $c,
            flags   => $data[0],
            channel => $data[1],
            day     => $data[2],
            start   => $data[3],
            stop    => $data[4],
            priority=> $data[5],
            lifetime=> $data[6],
            file    => $data[7],
            aux     => $data[8]
          };
          $obj->_insert($timer, 1);
        }
    }

    # Search for overlapping Timers
    my $overlapping = $obj->getOverlappingTimer();

    # Get timers by Autotimer
    my $aids = getDataByFields('AUTOTIMER', 'Id');
    $obj->getTimersByAutotimer($aids);

    # Get new timers by User
    if($oldTimers or exists $obj->{changedTimer}) {
        my $timers = $obj->getNewTimers($oldTimers);
        foreach my $timerdata (@$timers) {
            event sprintf('New timer "%s" with id: "%d"', $timerdata->{file}, $timerdata->{pos});
        }
        $obj->updated() if(scalar @$timers or exists $obj->{changedTimer});
        delete $obj->{changedTimer}  if(exists $obj->{changedTimer});
    }

    $obj->{REGISTER}++;
    if(scalar keys %$oldTimers != $c or $obj->{REGISTER} == 2) {
        # Event to signal we are finish to read
        event(sprintf('Reread %d timers and written into database!', $c));
    }

    $console->message(sprintf(gettext("%d timer written to database."), $c), {overlapping => $overlapping})
        if(ref $console and $console->typ ne 'AJAX');

    return 1;
}

# ------------------
sub readData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    if($obj->_readData($watcher,$console)) {
      $console->redirect({url => '?cmd=tlist', wait => 1})
        if(ref $console and $console->typ eq 'HTML');
    }
}

# Routine um Callbacks zu registrieren und
# diese nach dem Aktualisieren der Timer zu starten
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
sub list {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $text    = shift || '';

	  my $term;
	  my $search = '';
	  if($text and $text =~ /^[0-9a-f,_ ]+$/ and length($text) >= 32 ) {
      my @timers  = split(/[^0-9a-f]/, $text);
      $search = sprintf(" AND t.id in (%s)",join(',' => ('?') x @timers));
      foreach(@timers) { push(@{$term},$_); }
	  } elsif($text) {
      my $query = buildsearch("t.file,(SELECT description FROM EPG as e WHERE t.eventid = e.eventid LIMIT 1)",$text);
      $search = sprintf('AND ( %s )', $query->{query});
      foreach(@{$query->{term}}) { push(@{$term},$_); }
	  }

    my %f = (
        'id' => gettext('Service'),
        'flags' => gettext('Status'),
        'day' => gettext('Day'),
        'channel' => gettext('Channel'),
        'start' => gettext('Start'),
        'stop' => gettext('Stop'),
        'title' => gettext('Title'),
        'priority' => gettext('Priority')
    );

    my $sql = qq|
SELECT SQL_CACHE 
    t.id as \'$f{'id'}\',
    t.flags as \'$f{'flags'}\',
    c.Name as \'$f{'channel'}\',
    c.Pos as __pos,
    UNIX_TIMESTAMP(t.starttime) as \'$f{'day'}\',
    DATE_FORMAT(t.starttime, '%H:%i') as \'$f{'start'}\',
    DATE_FORMAT(t.stoptime, '%H:%i') as \'$f{'stop'}\',
    t.file as \'$f{'title'}\',
    t.priority as \'$f{'priority'}\',
    t.collision as __collision,
    t.eventid as __eventid,
    t.autotimerid as __autotimerid,
	  UNIX_TIMESTAMP(t.stoptime) - UNIX_TIMESTAMP(t.starttime) as __duration,
    (SELECT description
      FROM EPG as e
      WHERE t.eventid = e.eventid
      LIMIT 1) as __description,
    NOW() between starttime and stoptime AND (flags & 1) as __running 
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.stoptime > NOW()
    AND t.channel = c.Id
    $search
ORDER BY
    t.starttime
|;

    my $rows;
    if($console->{cgi} && $console->{cgi}->param('limit')) {
      # Query total count of rows
      my $rsth = $obj->{dbh}->prepare($sql);
        $rsth->execute(@{$term})
          or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
      $rows = $rsth->rows;

      # Add limit query
      if($console->{cgi}->param('start')) {
        $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
        $sql .= "," . CORE::int($console->{cgi}->param('limit'));
      } else {
        $sql .= " LIMIT " . CORE::int($console->{cgi}->param('limit'));
      }
    }

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@{$term})
      or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    $rows = $sth->rows unless($rows);

    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    unless($console->typ eq 'AJAX') {
      map {
          $_->[4] = datum($_->[4],'weekday');
      } @$erg;

      unshift(@$erg, $fields);
    }

    $console->table($erg, {
        cards => $obj->{DVBCards},
		    capacity => main::getModule('RECORDS')->{CapacityFree},
        rows => $rows
    });
}

# ------------------
sub getTimerById {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $tid = shift  || return error('No id defined!');

    my $sql = qq|
SELECT SQL_CACHE 
    t.id,
    t.flags,
    c.Name as Channel,
    c.Pos as __Pos,
    t.day as Date,
    t.start,
    t.stop,
    t.file,
    t.priority,
    UNIX_TIMESTAMP(t.starttime) as Day,
    t.collision,
    t.eventid,
    t.autotimerid
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.channel = c.Id
    and t.id = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer '%s' does not exist in the database!",$tid));
    return $sth->fetchrow_hashref();
}

# ------------------
sub getTimerByPos {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $tid = shift  || return error('No id defined!');

    my $sql = qq|
SELECT SQL_CACHE 
    t.id,
    t.flags,
    c.Name as Channel,
    c.Pos as __Pos,
    t.day as Date,
    t.start,
    t.stop,
    t.file,
    t.priority,
    UNIX_TIMESTAMP(t.starttime) as Day,
    t.collision,
    t.eventid,
    t.autotimerid
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.channel = c.Id
    and t.pos = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer '%s' does not exist in the database!",$tid));
    return $sth->fetchrow_hashref();
}
# ------------------
sub getRunningTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
		my $rowname = shift || 'id';
    my $sql = "SELECT SQL_CACHE $rowname from TIMERS where NOW() between starttime and stoptime AND (flags & 1)";
    my $erg = $obj->{dbh}->selectall_hashref($sql, $rowname);
    return $erg;
}

# ------------------
sub getNewTimers {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $oldTimers = shift || return;

    my $ret = [];
    foreach my $timerid (keys %$oldTimers) {
        if(! $oldTimers->{$timerid}->{checked}) {
            push(@$ret, $oldTimers->{$timerid});
        }
    }
    return $ret;
}

# ------------------
sub getCheckTimer {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $sql = qq|
SELECT SQL_CACHE  t.id as id,t.pos as pos, t.flags as flags,t.channel as channel,
        t.priority as priority, t.lifetime as lifetime,
        t.file as file, t.aux as aux,
        t.start as timerstart,t.stop as timerstop,

        UNIX_TIMESTAMP(e.starttime) as starttime,
        UNIX_TIMESTAMP(e.starttime) + e.duration as stoptime,
        UNIX_TIMESTAMP(e.vpstime) as vpsstart,
        UNIX_TIMESTAMP(e.vpstime) + e.duration as vpsstop,

        ABS(UNIX_TIMESTAMP(t.eventstarttime) - UNIX_TIMESTAMP(t.starttime)) as lead,
        ABS(UNIX_TIMESTAMP(t.stoptime)-(UNIX_TIMESTAMP(t.eventstarttime) + t.eventduration)) as lag

        FROM TIMERS as t, EPG as e 
        WHERE (flags & 1) 
        AND e.eventid > 0 
        AND t.eventid = e.eventid
        AND (
                   (((t.flags & 4) = 0) AND e.starttime != t.eventstarttime) 
                OR ((t.flags & 4) AND e.vpstime != t.eventstarttime) 
                OR (e.duration != t.eventduration)
            )
        AND SUBSTRING_INDEX( t.file , '~', 1 ) LIKE CONCAT('%', e.title ,'%')
|;
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'id');

    foreach my $t (keys %$erg) {
        my %tt;

        # Adjust start and stop times
        my $start;
        my $stop;

        if(($erg->{$t}->{flags} & 4)  # Use PDC time if used
           and $erg->{$t}->{vpsstart} 
           and $erg->{$t}->{vpsstop}) {
            $start = $erg->{$t}->{vpsstart};
            $stop = $erg->{$t}->{vpsstop};
        } else {
            $start = $erg->{$t}->{starttime} - $erg->{$t}->{lead};
            $stop  = $erg->{$t}->{stoptime} + $erg->{$t}->{lag};
        }

        # Format parameterhash for saveTimer
        my $tt = {
            pos       => $erg->{$t}->{pos},
            activ     => (($erg->{$t}->{flags} & 1) ? 'y' : 'n'),
            vps       => (($erg->{$t}->{flags} & 4) ? 'y' : 'n'), 
            channel   => $erg->{$t}->{channel},
            file      => $erg->{$t}->{file},
            aux       => $erg->{$t}->{aux},
            day       => my_strftime("%Y-%m-%d",$start),
            start     => my_strftime("%H%M",$start),
            stop      => my_strftime("%H%M",$stop),
            priority  => $erg->{$t}->{priority},
            lifetime  => $erg->{$t}->{lifetime}
      	};

        debug sprintf("Adjust timer %d (%s) at %s : from %s - %s to %s - %s", 
                      $tt->{pos}, 
                      $tt->{file}, 
                      $tt->{day}, 
                      fmttime($erg->{$t}->{timerstart}), fmttime($erg->{$t}->{timerstop}),
                      fmttime($tt->{start}),fmttime($tt->{stop}));

        $obj->saveTimer($tt);
    }
    return $erg;
}

# ------------------
sub getPos {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $tid = shift  || return error('No id defined!');

    my $sql = qq|
SELECT SQL_CACHE 
    pos from TIMERS as t
where
    t.id = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer '%s' does not exist in the database!",$tid));
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{pos} : 0;
}

# ------------------
sub getEpgDesc {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $tid = shift  || return error('No id defined!');

    my $sql = qq|
SELECT SQL_CACHE 
    description from TIMERS as t, EPG as e
where
    e.eventid > 0 and
    t.eventid = e.eventid and
    t.id = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer '%s' does not exist in the database!",$tid));
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{description} : '';
}

# ------------------
sub getOverlappingTimer {
# ------------------
    my $obj  = shift || return error('No object defined!');

    my $sql = qq|
SELECT SQL_CACHE 
    t.id,
    t.priority,
    t.starttime,
    t.stoptime,
    c.TID as transponderid,
    LEFT(c.Source,1) as source
from TIMERS as t,
    CHANNELS as c
where t.channel = c.Id
|;
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'id');
    my $return;

    my $sth = $obj->{dbh}->prepare("UPDATE TIMERS SET collision = ? WHERE id = ?");
    foreach my $tid (keys %$erg) {
        my $result = $obj->checkOverlapping($erg->{$tid});
        if(ref $result eq 'ARRAY' and scalar @$result) {
            my $col = join(',',@$result);
            $sth->execute($col,$tid);
            $return->{"timer_$tid"} = $col;
        }


    }
    return $return;
}

# ------------------
sub checkOverlapping {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $data = shift  || return error('No data defined!');

    my $starttime =  $data->{starttime};
    my $stoptime  =  $data->{stoptime};
    my $transponder   =  $data->{transponderid};
    my $source        =  $data->{source};
    my $Priority      =  $data->{priority} || $obj->{Priority};
    my $tid           =  $data->{id} || 0;

    my $sql = qq|
SELECT SQL_CACHE 
    t.id,
    t.priority,
    c.TID
FROM
    TIMERS as t, CHANNELS as c
WHERE
    ((? between t.starttime AND t.stoptime)
     OR (? between t.starttime AND t.stoptime)
     OR (t.starttime between ? AND ?)
     OR (t.stoptime between ? AND ?))
    AND t.id != ?
    AND (t.flags & 1)
    AND t.channel = c.Id
    AND c.TID != ?
    AND LEFT(c.Source,1) = ?
ORDER BY
    t.priority desc
|;
    my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute($starttime,$stoptime,
            $starttime,$stoptime,
            $starttime,$stoptime,
            $tid,$transponder,$source)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $result = $sth->fetchall_arrayref();

    if(scalar @{$result}) {
            my $coltext = [];
            foreach my $probant (@{$result}) {

               if(defined $probant->[0]) {

               # current timer has higher Priority
               last
                  if($Priority > $probant->[1]);


               # Store conflict line at line
               my $col = sprintf('%s:%s',
                                    $probant->[0],
                                    $probant->[1]);

               # insert double transponder, on same line
               my $n = 0;
               foreach my $trans (@{$result}) {

                    if(defined $trans->[0]
                         && $probant->[0] ne $trans->[0]
                         && $probant->[2] eq $trans->[2]) {

                        $col .= sprintf('|%s:%s',
                                    $trans->[0],
                                    $trans->[1]);

                       undef @{$result}[$n]->[0];
                    }
                    ++$n;
               }
               # Add line
               push(@$coltext,$col);
           }
        }
        if(scalar(@$coltext) > $obj->{DVBCards} - 1) {
            return $coltext;
        }
    }
}

# ------------------
sub getNextTimer {
# ------------------
    my $obj = shift  || return error('No object defined!');

    my $erg = $obj->{svdrp}->command('NEXT abs');
    my @eerg = grep(/^250/, @$erg);
    if(scalar @eerg and my ($errcode, $nextTimer, $zeit) = split(/\s+/, $eerg[0])) {
        return if(
            ! $nextTimer
            or $zeit < time
            or (ref $obj->{NextTimerEvent} and $obj->{NextTimerEvent}->at == $zeit)
        );

        my $timer = $obj->getTimerByPos($nextTimer);

        $obj->{NextTimerEvent} = Event->timer(
            at  => $zeit,
            data  => $timer,
            hard => 1,
            repeat => 0,
            prio => 2,  # -1 very hard ... 6 very low
            cb => sub{
                my $event = shift;
                my $watcher = $event->w;
                my $data = $watcher->data;

                my $modR = main::getModule('REPORT');
                $modR->news(
                    sprintf(gettext("Timer title '%s' has started the recording!"), $data->{file}),
                    sprintf(gettext("on channel: %s to %s"), $data->{channel}, fmttime($data->{stop})),
                    'tedit',
                    $data->{id},
                    'harmless'
                );
                $watcher->cancel;
            },
        );
    }
}

# Find EPG to selected timer
# ------------------
sub _getNextEpgId {
# ------------------
    my $obj  = shift || return error('No object defined!');
    my $timer  = shift || return error('No data defined!');

    my $e;
    my @file = split('~', $timer->{file});
    my $timemode = ($timer->{flags} & 4) ? 'vpstime' : 'starttime';
    if(scalar @file >= 2) { # title and subtitle defined
        my $sth = $obj->{dbh}->prepare(sprintf(qq|
            SELECT SQL_CACHE eventid,%s as starttime,duration from EPG
            WHERE
                channel_id = ? 
                AND ((UNIX_TIMESTAMP(%s) + (duration/2)) between  ?  and  ? )
                AND (title like ? or title like ? )
            ORDER BY ABS(( ? )-UNIX_TIMESTAMP(%s)) LIMIT 1
            |,$timemode,$timemode,$timemode));
        if(!$sth->execute($timer->{channel},
                      $timer->{start},
                      $timer->{stop},
                      '%'.$file[-2].'%',
                      '%'.$file[-1].'%',
                      $timer->{start})) {
            lg sprintf("Couldn't find epg event for timer with id %d - %s", $timer->{pos} , $timer->{file} );
            return 0;
        }
        $e = $sth->fetchrow_hashref();

    } else {
        my $sth = $obj->{dbh}->prepare(sprintf(qq|
            SELECT SQL_CACHE eventid,%s as starttime,duration from EPG
            WHERE
                channel_id = ? 
                AND ((UNIX_TIMESTAMP(%s) + (duration/2)) between  ?  and  ? )
                AND (title like ? )
            ORDER BY ABS(( ? )-UNIX_TIMESTAMP(%s)) LIMIT 1
            |,$timemode,$timemode,$timemode));
        if(!$sth->execute($timer->{channel},
                      $timer->{start},
                      $timer->{stop},
                      '%'.$timer->{file}.'%',
                      $timer->{start})) {
            lg sprintf("Couldn't find epg event for timer with id %d - %s", $timer->{pos} , $timer->{file} );
            return 0;
        }
        $e = $sth->fetchrow_hashref();
    }


    lg sprintf("Couldn't find epg event for timer with id %d - %s", $timer->{pos} , $timer->{file} )
        if(not exists $e->{eventid});
    return $e;
}

# The following subroutines is stolen from vdradmind and vdradmin-0.97-am
# Thanks on Cooper and Thomas for this great work!
# $obj->getNextTime('MDMDFSS', 1300, 1200)
# ------------------
sub getNextTime {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $dor = shift || return error('No day defined!');
    my $start = shift || return error('No start time defined!');
    my $stop =  shift || return error('No stop time defined!');

    $start = sprintf('%04d', $start);
    $stop = sprintf('%04d', $stop);

    my ($startsse, $stopsse);
    if(length($dor) == 7) { # repeating timer => MTWTFSS
        $startsse = my_mktime(substr($start, 2, 2), substr($start, 0, 2),
                       my_strftime("%d"), (my_strftime("%m") - 1), my_strftime("%Y"));
        $stopsse  = my_mktime(substr($stop, 2, 2), substr($stop, 0, 2),
                       my_strftime("%d"), (my_strftime("%m") - 1), my_strftime("%Y"));
        $stopsse += 86400 if($stopsse < $startsse);

        my $weekday = ((localtime(time))[6] + 6) % 7;
        my $perrec = join("", substr($dor, $weekday), substr($dor, 0, $weekday));
        $perrec =~ m/^-+/g;

        my $off = (pos $perrec || 0) * 86400;
        if($off == 0 && $stopsse < time) {
            #$weekday = ($weekday + 1) % 7;
            $perrec = join("", substr($dor, ($weekday + 1) % 7), substr($dor, 0, ($weekday + 1) % 7));
            $perrec =~ m/^-+/g;
            $off = ((pos $perrec || 0) + 1) * 86400;
        }
        $startsse += $off;
        $stopsse += $off;
    } elsif(length($dor) == 18) { # first-day timer => MTWTFSS@2005-03-13
        $dor =~ /.{7}\@(\d{4})-(\d{2})-(\d{2})/;
        $startsse = my_mktime(substr($start, 2, 2),
                substr($start, 0, 2), $3, ($2 - 1), $1);
        # 31 + 1 = ??
        $stopsse = my_mktime(substr($stop, 2, 2),
                substr($stop, 0, 2), $stop > $start ? $3 : $3 + 1,
                ($2 - 1), $1);
    } else { # regular timer
      if ($dor =~ /(\d{4})-(\d{2})-(\d{2})/) { # vdr >= 1.3.23 => 2005-03-13
        $startsse = my_mktime(substr($start, 2, 2),
                              substr($start, 0, 2), $3, ($2 - 1), $1);

        $stopsse = my_mktime(substr($stop, 2, 2),
                             substr($stop, 0, 2), $stop > $start ? $3 : $3 + 1, ($2 - 1), $1);
      }
      else { # vdr < 1.3.23 => 13
        $startsse = my_mktime(substr($start, 2, 2),
                substr($start, 0, 2), $dor, (my_strftime("%m") - 1),
                my_strftime("%Y"));

        $stopsse = my_mktime(substr($stop, 2, 2),
                substr($stop, 0, 2), $stop > $start ? $dor : $dor + 1,
                (my_strftime("%m") - 1), my_strftime("%Y"));

        # move timers which have expired one month into the future
        if(length($dor) != 7 && $stopsse < time) {
          $startsse = my_mktime(substr($start, 2, 2),
                                substr($start, 0, 2), $dor, (my_strftime("%m") % 12),
                                (my_strftime("%Y") + (my_strftime("%m") == 12 ? 1 : 0)));

          $stopsse = my_mktime(substr($stop, 2, 2),
                               substr($stop, 0, 2), $stop > $start ? $dor : $dor + 1,
                               (my_strftime("%m") % 12),
                               (my_strftime("%Y") + (my_strftime("%m") == 12 ? 1 : 0)));
        }
      }
    }

    my $ret = {
        start => $startsse,
        stop => $stopsse,
    };
    return $ret;
}

# ------------------
# Name:  getTimersByAutotimer
# Descr: Routine group Autotimer to Timers.
# Usage: $hash = $obj->getTimersByAutotimer([$aid, $aid, $aid, ...]);
# ------------------
sub getTimersByAutotimer {
    my $obj = shift  || return error('No object defined!');
    my $aids = shift || return $obj->{AIDS};

    $obj->{AIDS} = {};
    for my $aid (@$aids) {
        $obj->{AIDS}->{$aid} = {
            allTimer => [],
            activeTimer => [],
            deactiveTimer => [],
        };
        my $erg = getDataBySearch('TIMERS', 'autotimerid = ?', $aid);
        map {
            my $type = ($_->[1] ? 'activeTimer' : 'deactiveTimer');
            push(@{$obj->{AIDS}->{$aid}->{$type}}, $_->[0]);
            push(@{$obj->{AIDS}->{$aid}->{allTimer}}, $_->[0]);
        } @$erg;
    }
    return $obj->{AIDS};
}

# ------------------
# Name:  getRootDirs
# Descr: Get first root dir's.
# Usage: $hash = $obj->getRootDirs([$count]);
# ------------------
sub getRootDirs {
    my $obj = shift  || return error('No object defined!');
		my $count = shift || 1;
    my $sql = "SELECT SQL_CACHE distinct SUBSTRING_INDEX(file,'~',$count) from TIMERS;";
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
		my @ret;
		for(@$erg) {
			push(@ret, $_->[0]);
		}
		return \@ret;
}

sub my_mktime {
    my $sec  = 0;
    my $min = shift;
    my $hour = shift;
    my $mday = shift;
    my $mon  = shift;
    my $year = shift() - 1900;

    return mktime($sec, $min, $hour, $mday, $mon, $year, 0, 0, -1);
}

sub my_strftime {
    my $format = shift;
    my $time = shift || time;
    return(strftime($format, localtime($time)));
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
        file
    FROM
        TIMERS
    WHERE
    	( file LIKE ? )
    GROUP BY
        file
    ORDER BY
        file
    LIMIT 25
        |;
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute('%'.$search.'%')
            or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}

1;


1;
