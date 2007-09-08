package XXV::MODULES::TIMERS;

use strict;
use Tools;
use POSIX ":sys_wait_h", qw(strftime mktime);
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'TIMERS',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module parse the timers.conf and save this in the database.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Status => sub{ $obj->status(@_) },
        Preferences => {
            interval => {
                description => gettext('How often timers are to be updated (in seconds)'),
                default     => 30 * 60,
                type        => 'integer',
                required    => gettext("This is required!"),
            },
            prevminutes => {
                description => gettext('Buffer time in minutes before the scheduled end of the recorded program.'),
                default     => 5,
                type        => 'integer',
            },
            afterminutes => {
                description => gettext('Buffer time in minutes after the scheduled end of the recorded program.'),
                default     => 5,
                type        => 'integer',
            },
            Priority => {
                description => gettext('Defining the priority of this timer and of recordings created by this timer.'),
                default     => 50,
                type        => 'integer',
            },
            Lifetime => {
                description => gettext('The guaranteed lifetime (in days) of a recording created by this timer'),
                default     => 50,
                type        => 'integer',
            },
            DVBCards => {
                description => gettext('How much DVB cards in your system?'),
                default     => 1,
                type        => 'integer',
            },
            deactive => {
                description => gettext('Delete inactive timers after his end time?'),
                default     => 'n',
                type        => 'confirm',
            },
            usevpstime => {
                description => gettext('Use VPS start time?'),
                default     => 'n',
                type        => 'confirm',
            },
            adjust => {
                description => gettext('Timers adjust, if EPG entry were changed?'),
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
                description => gettext("Read timers and write into database"),
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
                Descr => gettext('Create event entries, if a new timer created by user.'),

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
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            return if($timer->{AutotimerId});
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});
                            my $title = sprintf(gettext("New timer found: %s"),$timer->{File});
                            my $description = sprintf(gettext("At: %s to %s\nDescription: %s"),
                                $timer->{NextStartTime},
                                fmttime($timer->{Stop}),
                                $desc && $desc->{description} ? $desc->{description} : ''
                                );

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            my $soap = main::getModule('SHARE');
                            my $level = 1;
                            if($timer->{AutotimerId}) {
                                $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 2 : 3);
                            } else {
                                $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 4 : 5);
                            }

                            if($timer->{eventid}) {
                                my $event = main::getModule('EPG')->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                            }
                        }|,
                ],

            },
            'deleteTimer' => {
                Descr => gettext('Create event entries, if timer deleted by user.'),
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
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            my $title = sprintf(gettext("Timer deleted: %s"),$timer->{File});
                            my $desc = getDataById($timer->{eventid}, 'EPG', 'eventid') if($timer->{eventid});
                            my $description = sprintf(gettext("At: %s to %s\nDescription: %s"),
                                $timer->{NextStartTime},
                                fmttime($timer->{Stop}),
                                $desc && $desc->{description} ? $desc->{description} : ''
                                );

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
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
                Descr => gettext('Create event entries, if timer toggled by user.'),
                Level => 'interesting',
                SearchForEvent => {
                    Msg => 'modt',
                },
                Match => {
                    TimerId => qr/modt\s+(\d+)\s(on|off)/s,
                    Type    => qr/modt\s+\d+\s+(on|off)/s,
                },
                Actions => [
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            my $title = sprintf(gettext("Timer toggled: %s to %s"),$timer->{File},$args->{Type});
                            my $description = sprintf(gettext("Description: %s\nAt: %s to %s"),
                                $timer->{Summary},
                                $timer->{NextStartTime},
                                fmttime($timer->{Stop})
                                );

                            main::getModule('REPORT')->news($title, $description, "display", $timer->{eventid}, $event->{Level});
                        }
                    |,
                    q|sub{  my $args = shift;
                            my $event = shift;
                            my $timer  = getDataById($args->{TimerId}, 'TIMERS', 'Id');
                            my $soap = main::getModule('SHARE');
                            my $level = ($args->{Type} eq 'off' ? 1 : 2);
                            if($timer->{AutotimerId} and $args->{Type} eq 'on') {
                                $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 2 : 3);
                            } elsif($args->{Type} eq 'on') {
                                $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 4 : 5);
                            }

                            if($timer->{eventid}) {
                                my $event = main::getModule('EPG')->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
                            }
                        }|,
                ],
            },
            'updateTimer' => {
                Descr => gettext('Create event entries, if timer updated.'),
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
                            my $soap = main::getModule('SHARE');
                            my $epg = main::getModule('EPG');
                            for (my $i = 1; $i<=$args->{HighId}; $i++) {
                                my $timer  = getDataById($i, 'TIMERS', 'Id');

                                my $level = 1;
                                if($timer->{AutotimerId} and ($timer->{Status} & 1)) {
                                    $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 2 : 3);
                                } elsif($timer->{Status} & 1) {
                                    $level = (($timer->{Priority} <= 50 or $timer->{Lifetime} < 33) ? 4 : 5);
                                }

                                if($timer->{eventid}) {
                                    my $event = $epg->getId($timer->{eventid}, 'UNIX_TIMESTAMP(starttime) + duration as STOPTIME');
                                    $soap->setEventLevel($timer->{eventid}, $level, $event->{STOPTIME});
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
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift || 0;

    my $total = 0;
    {
        my $sth = $obj->{dbh}->prepare("select count(*) as count from TIMERS");
        if(!$sth->execute())
        {
            error sprintf("Can't execute query: %s.",$sth->errstr);
        } else {
            my $erg = $sth->fetchrow_hashref();
            $total = $erg->{count} if($erg && $erg->{count});
        }
    }

    return {
        message => sprintf(gettext('%d Timers exists.'), $total),
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
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    # read the DB Handle
    $self->{dbh} = delete $attr{'-dbh'};

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize module');

  	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    return 0, panic("Session to database is'nt connected")
      unless($obj->{dbh});

    # remove old table, if updated rows
    tableUpdated($obj->{dbh},'TIMERS',19,1);

    # Look for table or create this table
    my $version = main::getVersion;
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS TIMERS (
          Id int(11) unsigned NOT NULL,
          Status char(1) default 1,
          ChannelID varchar(100) NOT NULL default '',
          Day varchar(20) default '-------',
          Start int(11) unsigned,
          Stop int(11) unsigned,
          Priority tinyint(2),
          Lifetime tinyint(2),
          File text,
          Summary text default '',
          NextStartTime datetime,
          NextStopTime datetime,
          Collision varchar(100) default '0',
          eventid bigint unsigned default '0',
          eventstarttime datetime,
          eventduration int unsigned default '0',
          AutotimerId int(11) unsigned default '0',
          addtime timestamp,
          Checked char(1) default 0,
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    $obj->{newTimerFormat} = 0;
    $obj->{after_updated} = [];

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Can't get modul SVDRP");
           return 0;
        }

        $obj->readData();

        # Interval to read timers and put to DB
        Event->timer(
          interval => $obj->{interval},
          prio => 6,  # -1 very hard ... 6 very low
          cb => sub{
            $obj->readData();
          }
        );
        return 1;
    }, "TIMERS: Store timers in database ...", 10);


    return 1;
}

# ------------------
sub saveTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || return error('No Data to Save!');
    my $timerid = shift || 0;

    my $status = ($data->{Activ} eq 'y' ? 1 : 0);
       $status |= ($data->{VPS} eq 'y' ? 4 : 0);

    $data->{File} =~ s/:/|/g;
    $data->{File} =~ s/(\r|\n)//sig;

    my $erg = $obj->{svdrp}->command(
        sprintf("%s %s:%s:%s:%s:%s:%s:%s:%s:%s",
            $timerid ? "modt $timerid" : "newt",
            $status,
            $data->{ChannelID},
            $data->{Day},
            $data->{Start},
            $data->{Stop},
            int($data->{Priority}),
            int($data->{Lifetime}),
            $data->{File},
            ($data->{Summary} || '')
        )
    );

    # Save shortly this timer in DB if this only a new timer (at)
    # Very Important for Autotimer!
    my $pos = $1 if($erg->[1] =~ /^250\s+(\d+)/);
    if(! $timerid and $pos) {
        $obj->insert([
                $status,
                $data->{ChannelID},
                $data->{Day},
                $data->{Start},
                $data->{Stop},
                int($data->{Priority}),
                int($data->{Lifetime}),
                $data->{File},
	            ($data->{Summary} || '')
                ], $pos);
    }

    event('Save timer "%s" with TimerId: "%d"', $data->{File}, $pos);

    return $erg;
}

# ------------------
sub newTimer {
# ------------------
    my $obj     = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $epgid   = shift || 0;
    my $epg     = shift || 0;


    if($epgid and not ref $epg) {
        my $sth = $obj->{dbh}->prepare(
qq|
SELECT
    eventid,
    channel_id,
    description as Summary,
    CONCAT_WS('~', title, subtitle) as File,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) - ? ), '%d') as Day,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) - ? ), '%H%i') as Start,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(starttime) + duration + ? ), '%H%i') as Stop,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(vpstime)), '%H%i') as VpsStart,
    DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(vpstime) + duration), '%H%i') as VpsStop
FROM
    EPG
WHERE
    eventid = ?
|);
        $sth->execute($obj->{prevminutes} * 60, $obj->{prevminutes} * 60, $obj->{afterminutes} * 60, $epgid)
            or return $console->err(sprintf(gettext("Event ID '%s' does not exist in the database!"),$epgid));
        $epg = $sth->fetchrow_hashref();
    }
    if(not ref $epg) {
		my $t = time;
   	    $epg = {
            channel_id => '',
            File => '',
            Summary => '',
            Day => $obj->{newTimerFormat}?my_strftime("%Y-%m-%d",$t):my_strftime("%d",$t),
            Start => my_strftime("%H%M",$t),
            Stop => my_strftime("%H%M",$t)
    	};
    }

    $epg->{Status} = '1'
         if(not defined $epg->{Status});
    $epg->{Priority} = $obj->{Priority}
         if(not defined $epg->{Priority});
    $epg->{Lifetime} = $obj->{Lifetime}
         if(not defined $epg->{Lifetime});
	if(main::getVdrVersion() >= 10344) {
    	$epg->{desc} = $epg->{Summary};
    	$epg->{Summary} = ""
    }
    if($epg->{VpsStart} && $obj->{usevpstime} eq 'y') {
        $epg->{Status} |= 4;
        $epg->{Start} = $epg->{VpsStart};
        $epg->{Stop} = $epg->{VpsStop};
    }

    $obj->editTimer($watcher, $console, 0, $epg);
}

# ------------------
sub editTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $timerid = shift || 0;   # If timerid the edittimer
    my $data    = shift || 0;  # Data for defaults

    my $timerData;
    if($timerid and not ref $data) {
        my $sth = $obj->{dbh}->prepare(
qq|
SELECT
    Id, 
    ChannelID as channel_id, 
    File, 
    Summary, 
    Start, 
    Stop, 
    Day, 
    Priority, 
    Lifetime, 
    Status
FROM
    TIMERS
WHERE
    Id = ?
|);
        $sth->execute($timerid)
            or return $console->err(sprintf(gettext("Timer ID '%s' does not exist in the database!"),$timerid));
        $timerData = $sth->fetchrow_hashref();
    } elsif (ref $data eq 'HASH') {
        $timerData = $data;
    }

    $timerData->{Summary} =~ s/(\r|\n)//sig
        if(defined $timerData->{Summary});

    my $mod = main::getModule('CHANNELS');
    my $con = $console->typ eq "CONSOLE";

    my $questions = [
        'Id' => {
            typ     => 'hidden',
            def     => $timerData->{Id} || 0,
        },
        'Activ' => {
            typ     => 'confirm',
            def     => (defined $timerData->{Status} and ($timerData->{Status} & 1) ? 'y' : 'n'),
            msg     => gettext('Switch this timer on?'),
        },
        'VPS' => {
            typ     => 'confirm',
            def     => (defined $timerData->{Status} and ($timerData->{Status} & 4) ? 'y' : 'n'),
            msg     => gettext('VPS for this timer on?'),
        },
        'ChannelID' => {
            typ     => 'list',
            def     => $con ? $mod->ChannelToPos($timerData->{channel_id}) : $timerData->{channel_id},
            choices => $con ? $mod->ChannelArray('Name') : $mod->ChannelIDArray('Name'),
            msg     => gettext('Which channel should recorded?'),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift || return;

                if(my $name = $mod->ChannelToName($value)) {
                    $timerData->{Channel} = $value;
                    return $value;
                } elsif(my $ch = $mod->PosToChannel($value) || $mod->NameToChannel($value) ) {
                    $timerData->{Channel} = $value;
                    return $ch;
                } elsif( ! $mod->NameToChannel($value)) {
                    return undef, sprintf(gettext("This channel '%s' does not exist!"),$value);
                } else {
                   return undef, gettext("This is required!");
                }
            },
        },
        'Day' => {
            typ     => $con ? 'string' : 'date',
            def     => $timerData->{Day},
            msg     => gettext("Please enter a day (1 to 31) or the weekday in format 'MDMDFSS'."),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift || return;
                if(($value =~ /^\d+$/ and int($value) <= 31 and int($value) > 0)            # 13
                        or ($obj->{newTimerFormat} and $value =~ /^\d{4}\-\d{2}-\d{2}$/sig) # 2005-03-13
                        or $value =~ /^\S{7}\@\d{4}\-\d{2}-\d{2}$/sig                       # MTWTFSS@2005-03-13
                        or $value =~ /^\S{7}\@\d{2}$/sig                                    # MTWTFSS@13
                        or $value =~ /^\S{7}$/) {                                           # MTWTFSS
                    return $value;
                } else {
                    return undef, gettext('No right day or corrupt format!');
                }
            },
        },
        'Start' => {
            typ     => 'string',
            def     => sub{
                return fmttime($timerData->{Start});
                },
            msg     => gettext("Starttime in format 'HH:MM'"),
            check   => sub{
                my $value = shift;
                $value = fmttime($value) if($value =~ /^\d+$/sig);
                return undef, gettext('No right time!') if($value !~ /^\d+:\d+$/sig);
                my @v = split(':', $value);
                $value = sprintf('%02d%02d',$v[0],$v[1]);
                if(int($value) < 2400 and int($value) >= 0) {
                    return sprintf('%04d',$value);
                } else {
                    return undef, gettext('No right time!');
                }
            },
        },
        'Stop' => {
            typ     => 'string',
            def     => sub{
                    return fmttime($timerData->{Stop} || 0 );
                },
            msg     => gettext("Endtime in format 'HH:MM'"),
            check   => sub{
                my $value = shift;
                $value = fmttime($value) if($value =~ /^\d+$/sig);
                return undef, gettext('No right time!') if($value !~ /^\d+:\d+$/sig);
                my @v = split(':', $value);
                $value = sprintf('%02d%02d',$v[0],$v[1]);
                if(int($value) < 2400 and int($value) >= 0) {
                    return sprintf('%04d',$value);
                } else {
                    return undef, gettext('No right time!');
                }
            },
        },
        'Priority' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Priority (0 .. %d)'),$console->{USER}->{MaxPriority} ? $console->{USER}->{MaxPriority} : 99 ),
            def     => int($timerData->{Priority}),
            check   => sub{
                my $value = shift || 0;
                if($value =~ /^\d+$/sig and $value >= 0 and $value < 100) {
                    if($console->{USER}->{MaxPriority} and $value > $console->{USER}->{MaxPriority}) {
                        return undef, sprintf(gettext('Sorry, but maximum priority is limited on %d!'), $console->{USER}->{MaxPriority});
                    }
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'Lifetime' => {
            typ     => 'integer',
            msg     => sprintf(gettext('Lifetime (0 .. %d)'),$console->{USER}->{MaxLifeTime} ? $console->{USER}->{MaxLifeTime} : 99 ),
            def     => int($timerData->{Lifetime}),
            check   => sub{
                my $value = shift || 0;
                if($value =~ /^\d+$/sig and $value >= 0 and $value < 100) {
                    if($console->{USER}->{MaxLifeTime} and $value > $console->{USER}->{MaxLifeTime}) {
                        return undef, sprintf(gettext('Sorry, but maximum lifetime is limited on %d!'), $console->{USER}->{MaxLifeTime});
                    }
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'File' => {
            msg     => gettext('Title of recording'),
            def     => $timerData->{File},
            req     => gettext("This is required!"),
        },
    ];

    my $Summary = $timerData->{Summary};
    $Summary =~s/\#~AT\[(\d+)\]//g;

	if(main::getVdrVersion() >= 10344){
        if($timerData->{Id} || $timerData->{desc}) {
            my $desc = $timerData->{desc} || $obj->getEpgDesc($timerData->{Id});
            if($desc) {
        		push(@$questions,
        		'Description' => {
                    msg   =>  gettext('Description'),
                    typ     => 'string',
                    def   => $desc,
                    readonly => 1
                });
            }
        }

		push(@$questions,
		'Summary' => {
            typ     => 'hidden',
            def   => $Summary,
        });
	} else {
		push(@$questions,
		'Summary' => {
            msg   =>  gettext('Additional description'),
            def   => $Summary,
            check   => sub{
                my $value = shift || return;
                $value =~ s/(\r|\n)//sig;
                return $value;
            },
        });
	}
    # Ask Questions
    my $datasave = $console->question(($timerid ? gettext('Edit timer')
                                                : gettext('New timer')), $questions, $data);

    if(ref $datasave eq 'HASH') {
        my $erg = $obj->saveTimer($datasave, $timerid);

        my $error;
        foreach my $zeile (@$erg) {
            if($zeile =~ /^(\d{3})\s+(.+)/) {
                $error = $2 if(int($1) >= 500);
            }
        }

        unless($error) {
            debug sprintf('%s timer with title "%s" is saved%s',
                ($timerid ? 'Changed' : 'New'),
                $data->{File},
                ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
                );
                $console->message($erg);
        } else {
            error sprintf('%s timer with title "%s" does\'nt saved : %s',
                ($timerid ? 'Changed' : 'New'),
                $data->{File},
                $error
                );
                $console->err($erg);
        }
        $obj->readData($watcher,$console);
        $console->redirect({url => $console->{browser}->{Referer}, wait => 2})
            if($console->typ eq 'HTML');
    }
}

# ------------------
sub deleteTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $timerid = shift || return $console->err(gettext("No Timer ID to delete! Please use tdelete 'tid'"));   # If timerid the edittimer
    my $answer  = shift || 0;

    my @timers  = reverse sort{ $a <=> $b } split(/[^0-9]/, $timerid);

    my $sql = sprintf('SELECT Id,File,ChannelID,NextStartTime,IF(Status & 1 and NOW() between NextStartTime and NextStopTime,1,0) as Running FROM TIMERS where Id in (%s)', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@timers)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_hashref('Id');

    my $mod = main::getModule('CHANNELS') or return;
    foreach my $tid (@timers) {
        unless(exists $data->{$tid}) {
            $console->err(sprintf(gettext("Timer with number '%s' does not exist in the database!"), $tid));
            next;
        }

        if(ref $console and $console->{TYP} eq 'CONSOLE') {
            $data->{$tid}->{ChannelID} = $mod->ChannelToName($data->{$tid}->{ChannelID});

            $console->table($data->{$tid});
            my $confirm = $console->confirm({
                typ   => 'confirm',
                def   => 'y',
                msg   => gettext('Are you sure to delete this timer?'),
            }, $answer);
            next if(!$answer eq 'y');
        }

        debug sprintf('Delete timer with title "%s"%s',
            $data->{$tid}->{File},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $obj->{svdrp}->queue_cmds(sprintf("modt %d off", $tid))
          if($data->{$tid}->{Running});
        $obj->{svdrp}->queue_cmds(sprintf("delt %d", $tid));
    }

    if($obj->{svdrp}->queue_cmds('COUNT')) {
        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
        $console->msg($erg, $obj->{svdrp}->err)
            if(ref $console);

        sleep(1);

        $obj->readData($watcher,$console);

        $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
            if(ref $console and $console->typ eq 'HTML');
    } else {
        $console->err(gettext("No timer to delete!"));
    }

    return 1;
}

# ------------------
sub toggleTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $timerid = shift || return $console->err(gettext("No Timer ID to toggle! Please use ttoggle 'id'"));   # If timerid the edittimer

    my @timers  = reverse sort{ $a <=> $b } split(/[^0-9]/, $timerid);

    my $sql = sprintf('SELECT Id,File,Status,NextStartTime, NextStopTime FROM TIMERS where Id in (%s)', join(',' => ('?') x @timers)); 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute(@timers)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_hashref('Id');
    my $ref;

    for my $timer (@timers) {

        unless(exists $data->{$timer}) {
            $console->err(sprintf(gettext("Timer with number '%s' does not exist in the database!"), $timer));
            next;
        }

        # Build query for all timers with possible collisions
        $ref .= " or '$data->{$timer}->{NextStartTime}' between NextStartTime and NextStopTime"
             .  " or '$data->{$timer}->{NextStopTime}'  between NextStartTime and NextStopTime";


    	my $status = (($data->{$timer}->{Status} & 1) ? 'off' : 'on');

        debug sprintf('Timer with title "%s" is %s%s',
            $data->{$timer}->{File},
            ($status eq 'on' ? 'activated' : 'deactivated'),
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $obj->{svdrp}->queue_cmds("modt $data->{$timer}->{Id} $status"); # Sammeln der Kommandos
    }

    if($obj->{svdrp}->queue_cmds('COUNT')) {

        my $erg = $obj->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
        $console->msg($erg, $obj->{svdrp}->err)
            if(ref $console and $console->typ ne 'AJAX');

        $obj->readData($watcher, $console);

        $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
            if(ref $console and $console->typ eq 'HTML');

        if(ref $console and $console->typ eq 'AJAX') {
          # { "data" : [ [ ID, ON, RUN, CONFLICT ], .... ] }
          # { "data" : [ [ 5, 1, 0, 0 ], .... ] }
          my $sql = sprintf('select Id, Status & 1 as Active, IF(NOW() between NextStartTime and NextStopTime,1,0) as Running, Collision from TIMERS where Id in (%s) %s',
                             join(',' => ('?') x @timers),$ref); 
          my $sth = $obj->{dbh}->prepare($sql);
          $sth->execute(@timers)
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
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
sub insert {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || return;
    my $pos = shift || return;
    my $checked = shift || 0;

    # import only status which used from vdr and thereby exclude eventid from vdradmin
    $data->[0] &= 15;

    # change pos to channelid, because change to telnet reader
    $data->[1] = $obj->{channels}->{$data->[1]}->{Id}
        if(index($data->[1], '-') < 0);

    # POS
    unshift(@$data, $pos);
    $data->[8] =~ s/\|/\:/g;

    # NextTime
    my $nexttime = $obj->getNextTime( $data->[3], $data->[4], $data->[5] )
        or return error(sprintf("Can't get time form this data: %s", join(' ', @$data)));
    push(@$data, $nexttime->{start}, $nexttime->{stop});

    # insert placeholder
    push(@$data, 0); # eventid
    push(@$data, 0); # eventstarttime
    push(@$data, 0); # eventduration

    # AutotimerId
    my $atxt = (split('~', $data->[9]))[-1];
    my $aid = $1 if(defined $atxt and $atxt =~ /AT\[(\d+)\]/);
    push(@$data, $aid || 0);

    # checked
    push(@$data, $checked);

    # Search for event at EPG
    my $e = $obj->_getNextEpgId( {
          Id        => $data->[0],
          ChannelID => $data->[2],
          File      => $data->[8],
          NextStartTime => $data->[10],
          NextStopTime => $data->[11],
        });
    if($e and exists $e->{eventid}) {
        $data->[12] = $e->{eventid};
        $data->[13] = $e->{starttime};
        $data->[14] = $e->{duration};
    }

    my $sth = $obj->{dbh}->prepare('REPLACE INTO TIMERS VALUES (?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?), FROM_UNIXTIME(?),0,?,?,?,?,NOW(),?)');
    $sth->execute( @$data );
}


# Read from svdrp (better for future development)
# ------------------
sub readData {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;

    # Search for old and deactivated Timers and delete this
    $obj->getOldDeactivTimer()
        if($obj->{deactive} eq 'y');

    # Search for correct times
    $obj->getCheckTimer()
      if($obj->{adjust} eq 'y');

    my $oldTimers = &getDataByTable('TIMERS');

    $obj->{dbh}->do('DELETE FROM TIMERS');

    # read from svdrp, because the
    # vdr edit the timers.conf to lazy ;)
    $obj->{channels} = main::getModule('CHANNELS')->ChannelHash('POS');
    my $tlist = $obj->{svdrp}->command('lstt');

    my $c = 0;
    foreach my $line (@$tlist) {
        next if(! $line or $line =~ /^22/);
        $line =~ s/^\d+[- ]+\d+\s//sig;
        $c++;
        my @data = split(':', $line, 9);

        $obj->insert(\@data, $c, 1)
            if(scalar @data > 2);
    }

    # Search for overlapping Timers
    my $overlapping = $obj->getOverlappingTimer();

    # Get timers by Autotimer
    my $aids = getDataByFields('AUTOTIMER', 'Id');
    $obj->getTimersByAutotimer($aids);

    # Get new timers by User
    if($oldTimers) {
        my $timers = $obj->getNewTimers($oldTimers);
        foreach my $timerdata (@$timers) {
            event('New timer "%s" with id: "%d"', $timerdata->{File}, $timerdata->{Id});
        }
        $obj->updated() if(scalar @$timers);
    }

    $obj->{REGISTER}++;
    if(scalar keys %$oldTimers != $c or $obj->{REGISTER} == 2) {
        # Event to signal we are finish to read
        event(sprintf('Reread %d timers and written to DB!', $c));
    }

    $console->message(sprintf(gettext("Write %d timers in database."), $c), {overlapping => $overlapping})
        if(ref $console and $console->typ ne 'AJAX');

    $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
        if(ref $console and $console->typ eq 'HTML');

    return 1;
}

# Routine um Callbacks zu registrieren und
# diese nach dem Aktualisieren der Timer zu starten
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
sub list {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $text    = shift || '';

	my $in = '';
	if($text and $text =~ /^[0-9,_ ]+$/ ) {
        my @timers  = split(/[^0-9]/, $text);
        $in = sprintf("and t.Id in ( %s )",join(',',@timers));
	} elsif($text) {
        $in = sprintf('and ( %s )', buildsearch("t.File,t.Summary",$text));
	}
    my %f = (
        'Id' => umlaute(gettext('Sv')),
        'Status' => umlaute(gettext('Status')),
        'Prg' => umlaute(gettext('Prg')),
        'Channel' => umlaute(gettext('Channel')),
        'Start' => umlaute(gettext('Start')),
        'Stop' => umlaute(gettext('Stop')),
        'File' => umlaute(gettext('File')),
        'Priority' => umlaute(gettext('Priority')),
    );

    my $sql = qq|
SELECT
    t.Id as $f{'Id'},
    t.Status as $f{'Status'},
    c.Name as $f{'Channel'},
    c.Pos as __Pos,
    t.Day as $f{'Prg'},
    DATE_FORMAT(t.NextStartTime, '%H:%i') as $f{'Start'},
    DATE_FORMAT(t.NextStopTime, '%H:%i') as $f{'Stop'},
    t.File as $f{'File'},
    t.Priority as $f{'Priority'},
    UNIX_TIMESTAMP(t.NextStartTime) as __Day,
    t.Collision as __Collision,
    t.eventid as __eventid,
    t.AutotimerId as __AutotimerId,
	  UNIX_TIMESTAMP(t.NextStopTime) - UNIX_TIMESTAMP(t.NextStartTime) as __Duration,
    e.description as __description
FROM
    TIMERS as t,
    CHANNELS as c,
    EPG as e
WHERE
    t.ChannelID = c.Id
    and (t.eventid = e.eventid)
    $in

UNION 

SELECT
    t.Id as $f{'Id'},
    t.Status as $f{'Status'},
    c.Name as $f{'Channel'},
    c.Pos as __Pos,
    t.Day as $f{'Prg'},
    DATE_FORMAT(t.NextStartTime, '%H:%i') as $f{'Start'},
    DATE_FORMAT(t.NextStopTime, '%H:%i') as $f{'Stop'},
    t.File as $f{'File'},
    t.Priority as $f{'Priority'},
    UNIX_TIMESTAMP(t.NextStartTime) as __Day,
    t.Collision as __Collision,
    t.eventid as __eventid,
    t.AutotimerId as __AutotimerId,
	  UNIX_TIMESTAMP(t.NextStopTime) - UNIX_TIMESTAMP(t.NextStartTime) as __Duration,
    "" as __description
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.ChannelID = c.Id
    and (t.eventid = 0)
    $in

ORDER BY
    __Day
|;

    my $fields = fields($obj->{dbh}, $sql);

    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    unshift(@$erg, $fields);
    $console->table($erg, {
        runningTimer => $obj->getRunningTimer,
        cards => $obj->{DVBCards},
		    capacity => main::getModule('RECORDS')->{CapacityFree},
    });
}

# ------------------
sub getTimerById {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $tid = shift  || return error ('No TimerId!' );

    my $sql = qq|
SELECT
    t.Id,
    t.Status,
    c.Name as Channel,
    c.Pos as __Pos,
    t.Day as Prg,
    t.Start,
    t.Stop,
    t.File,
    t.Priority,
    UNIX_TIMESTAMP(t.NextStartTime) as Day,
    t.Collision as Collision,
    t.eventid as eventid,
    t.AutotimerId as AutotimerId
FROM
    TIMERS as t,
    CHANNELS as c
WHERE
    t.ChannelID = c.Id
    and t.Id = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer ID '%s' does not exist in the database!",$tid));
    return $sth->fetchrow_hashref();
}


# ------------------
sub getRunningTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
		my $rowname = shift || 'Id';
    my $sql = "select $rowname from TIMERS where NOW() between NextStartTime and NextStopTime AND (Status & 1)";
    my $erg = $obj->{dbh}->selectall_hashref($sql, $rowname);
    return $erg;
}

# ------------------
sub getNewTimers {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $oldTimers = shift || return;

    my $ret = [];
    foreach my $timerid (keys %$oldTimers) {
        if(! $oldTimers->{$timerid}->{Checked}) {
            push(@$ret, $oldTimers->{$timerid});
        }
    }
    return $ret;
}

# ------------------
sub getOldDeactivTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $sql = "select Id from TIMERS where not (Status & 1) and UNIX_TIMESTAMP(NextStopTime) > UNIX_TIMESTAMP() + (60*60*24*28)";
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'Id');

    foreach my $t (reverse sort {$a <=> $b} keys %$erg) {
        $obj->{svdrp}->queue_cmds("delt $t");
    }
    $obj->{svdrp}->queue_cmds("CALL")
        if($obj->{svdrp}->queue_cmds("COUNT"));
    return $erg;
}

# ------------------
sub getCheckTimer {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $sql = qq|
SELECT t.Id as Id, t.Status as Status,t.ChannelID as ChannelID,
        t.Priority as Priority, t.Lifetime as Lifetime,
        t.File as File, t.Summary as Summary,
        t.Start as TimerStart,t.Stop as TimerStop,

        UNIX_TIMESTAMP(e.starttime) as starttime,
        UNIX_TIMESTAMP(e.starttime) + e.duration as stoptime,
        UNIX_TIMESTAMP(e.vpstime) as vpsstart,
        UNIX_TIMESTAMP(e.vpstime) + e.duration as vpsstop,

        ABS(UNIX_TIMESTAMP(t.eventstarttime) - UNIX_TIMESTAMP(NextStartTime)) as lead,
        ABS(UNIX_TIMESTAMP(NextStopTime)-(UNIX_TIMESTAMP(t.eventstarttime) + t.eventduration)) as lag

        FROM TIMERS as t, EPG as e 
        WHERE (Status & 1) 
        AND e.eventid > 0 
        AND t.eventid = e.eventid
        AND ((e.starttime != t.eventstarttime) OR (e.duration != t.eventduration))
        AND SUBSTRING_INDEX( t.File , '~', 1 ) LIKE CONCAT('%', e.title ,'%')
|;
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'Id');

    foreach my $t (keys %$erg) {
        my %tt;

#       dumper($erg->{$t});
        
        # Adjust start and stop times
        my $start;
        my $stop;

        if(($erg->{$t}->{Status} & 4)  # Use VPS Time if used
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
            Activ     => (($erg->{$t}->{Status} & 1) ? 'y' : 'n'),
            VPS       => (($erg->{$t}->{Status} & 4) ? 'y' : 'n'), 
            ChannelID => $erg->{$t}->{ChannelID},
            File      => $erg->{$t}->{File},
            Summary   => $erg->{$t}->{Summary},
            Day       => $obj->{newTimerFormat}?my_strftime("%Y-%m-%d",$start):my_strftime("%d",$start),
            Start     => my_strftime("%H%M",$start),
            Stop      => my_strftime("%H%M",$stop),
            Priority  => $erg->{$t}->{Priority},
            Lifetime  => $erg->{$t}->{Lifetime}
      	};

        my $timer = $erg->{$t}->{Id};

        debug sprintf("Adjust timer %d (%s) at %s : from %s - %s to %s - %s", 
                      $timer, 
                      $tt->{File}, 
                      $tt->{Day}, 
                      fmttime($erg->{$t}->{TimerStart}), fmttime($erg->{$t}->{TimerStop}),
                      fmttime($tt->{Start}),fmttime($tt->{Stop}));

        $obj->saveTimer($tt, $timer);
    }
    return $erg;
}

# ------------------
sub getEpgIds {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $sql = "select Id, Status & 1 as Status, eventid from TIMERS where eventid > 0";
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'eventid');
    return $erg;
}

# ------------------
sub getEpgDesc {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $tid = shift  || return error ('No TimerId!' );

    my $sql = qq|
select
    description from TIMERS as t, EPG as e
where
    e.eventid > 0 and
    t.eventid = e.eventid and
    t.id = ?
|;

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($tid)
        or return error(sprintf("Timer ID '%s' does not exist in the database!",$tid));
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{description} : '';
}

# ------------------
sub getOverlappingTimer {
# ------------------
    my $obj  = shift || return error ('No Object!' );

    my $sql = qq|
select
    TIMERS.Id,
    TIMERS.Priority,
    TIMERS.NextStartTime,
    TIMERS.NextStopTime,
    CHANNELS.TID as transponderid,
    LEFT(CHANNELS.Source,1) as source
from TIMERS,
    CHANNELS
where TIMERS.ChannelID = CHANNELS.Id
|;
    my $erg = $obj->{dbh}->selectall_hashref($sql, 'Id');
    my $return;

    my $sth = $obj->{dbh}->prepare("UPDATE TIMERS SET Collision = ? WHERE Id = ?");
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
    my $obj = shift  || return error ('No Object!' );
    my $data = shift  || return error ('No Data!' );

    my $NextStartTime =  $data->{NextStartTime};
    my $NextStopTime  =  $data->{NextStopTime};
    my $transponder   =  $data->{transponderid};
    my $source        =  $data->{source};
    my $Priority      =  $data->{Priority} || $obj->{Priority};
    my $tid           =  $data->{Id} || 0;

    my $sql = qq|
SELECT
    t.Id,
    t.Priority,
    c.TID
FROM
    TIMERS as t, CHANNELS as c
WHERE
    ((? between t.NextStartTime AND t.NextStopTime)
     OR (? between t.NextStartTime AND t.NextStopTime)
     OR (t.NextStartTime between ? AND ?)
     OR (t.NextStopTime between ? AND ?))
    AND t.Id != ?
    AND (t.Status & 1)
    AND t.ChannelID = c.Id
    AND c.TID != ?
    AND LEFT(c.Source,1) = ?
ORDER BY
    t.Priority desc
|;
    my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute($NextStartTime,$NextStopTime,
            $NextStartTime,$NextStopTime,
            $NextStartTime,$NextStopTime,
            $tid,$transponder,$source)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $result = $sth->fetchall_arrayref();

    if(scalar @{$result}) {
            my $coltext = [];
            foreach my $probant (@{$result}) {

               if(defined $probant->[0]) {

               # current timer has higher Priority
               last
                  if($Priority > $probant->[1]);


               # Store conflict line at line
               my $col = sprintf('%d:%d',
                                    $probant->[0],
                                    $probant->[1]);

               # insert double transponder, on same line
               my $n = 0;
               foreach my $trans (@{$result}) {

                    if(defined $trans->[0]
                         && $probant->[0] != $trans->[0]
                         && $probant->[2] == $trans->[2]) {

                        $col .= sprintf('|%d:%d',
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
    my $obj = shift  || return error ('No Object!' );

    my $erg = $obj->{svdrp}->command('NEXT abs');
    my @eerg = grep(/^250/, @$erg);
    if(scalar @eerg and my ($errcode, $nextTimer, $zeit) = split(/\s+/, $eerg[0])) {
        return if(
            ! $nextTimer
            or $zeit < time
            or (ref $obj->{NextTimerEvent} and $obj->{NextTimerEvent}->at == $zeit)
        );

        my $timer = $obj->getTimerById($nextTimer);

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

                my $reportmod = main::getModule('REPORT');
                $reportmod->news(
                    sprintf(gettext("Timer %d with title '%s' is start to recording!"), $data->{Id}, $data->{File}),
                    sprintf(gettext("on channel: %s until %s"), $data->{Channel}, fmttime($data->{Stop})),
                    'tedit',
                    $data->{Id},
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
    my $obj  = shift || return error ('No Object!' );
    my $timer  = shift || return error ('No Hash!' );

    my $e;
    my @file = split('~', $timer->{File});

    if(scalar @file >= 2) { # title and subtitle defined
        my $sth = $obj->{dbh}->prepare(qq|
            SELECT eventid,starttime,duration from EPG
            WHERE
                channel_id = ? 
                AND ((UNIX_TIMESTAMP(starttime) + (duration/2)) between  ?  and  ? )
                AND (title like ? or title like ? )
            ORDER BY ABS(( ? )-UNIX_TIMESTAMP(starttime)) LIMIT 1
            |);
        if(!$sth->execute($timer->{ChannelID},
                      $timer->{NextStartTime},
                      $timer->{NextStopTime},
                      '%'.$file[-2].'%',
                      '%'.$file[-1].'%',
                      $timer->{NextStartTime})) {
            lg sprintf("Can't find epg event for timer with id %d - %s", $timer->{Id} , $timer->{File} );
            return 0;
        }
        $e = $sth->fetchrow_hashref();

    } else {
        my $sth = $obj->{dbh}->prepare(qq|
            SELECT eventid,starttime,duration from EPG
            WHERE
                channel_id = ? 
                AND ((UNIX_TIMESTAMP(starttime) + (duration/2)) between  ?  and  ? )
                AND (title like ? )
            ORDER BY ABS(( ? )-UNIX_TIMESTAMP(starttime)) LIMIT 1
            |);
        if(!$sth->execute($timer->{ChannelID},
                      $timer->{NextStartTime},
                      $timer->{NextStopTime},
                      '%'.$timer->{File}.'%',
                      $timer->{NextStartTime})) {
            lg sprintf("Can't find epg event for timer with id %d - %s", $timer->{Id} , $timer->{File} );
            return 0;
        }
        $e = $sth->fetchrow_hashref();
    }


    lg sprintf("Can't find epg event for timer with id %d - %s", $timer->{Id} , $timer->{File} )
        if(not exists $e->{eventid});
    return $e;
}

# The following subroutines is stolen from vdradmind and vdradmin-0.97-am
# Thanks on Cooper and Thomas for this great work!
# $obj->getNextTime('MDMDFSS', 1300, 1200)
# ------------------
sub getNextTime {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $dor = shift || return error ('No Day!' );
    my $start = shift || return error ('No Starttime!' );
    my $stop =  shift || return error ('No Stoptime!' );

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
        $obj->{newTimerFormat} = 1;
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
    my $obj = shift  || return error ('No Object!' );
    my $aids = shift || return $obj->{AIDS};

    $obj->{AIDS} = {};
    for my $aid (@$aids) {
        $obj->{AIDS}->{$aid} = {
            allTimer => [],
            activeTimer => [],
            deactiveTimer => [],
        };
        my $erg = getDataBySearch('TIMERS', sprintf('AutotimerId = %d', $aid));
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
    my $obj = shift  || return error ('No Object!' );
		my $count = shift || 1;
    my $sql = "select distinct SUBSTRING_INDEX(File,'~',$count) from TIMERS;";
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
sub suggest {# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $search = shift;
    my $params  = shift;

    if($search) {
        my $sql = qq|
    SELECT
        File
    FROM
        TIMERS
    WHERE
    	( File LIKE ? )
    GROUP BY
        File
    ORDER BY
        File
    LIMIT 25
        |;
        my $sth = $obj->{dbh}->prepare($sql);
        $sth->execute('%'.$search.'%')
            or return error sprintf("Can't execute query: %s.",$sth->errstr);
        my $result = $sth->fetchall_arrayref();
        $console->table($result)
            if(ref $console && $result);
    }
}

1;


1;
