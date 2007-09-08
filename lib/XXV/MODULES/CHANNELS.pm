package XXV::MODULES::CHANNELS;

use strict;

use Tools;
use Locale::gettext;
use File::stat;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'CHANNELS',
        Prereq => {
        },
        Description => gettext('This module reads new channels and stores them in the database.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $obj->status(@_) },
        Preferences => {
            file => {
                description => gettext('Location of channels.conf on your system.'),
                default     => '/var/lib/vdr/channels.conf',
                type        => 'file',
                required    => gettext('This is required!'),
            },
            interval => {
                description => gettext('How often channels are to be updated (in seconds)'),
                default     => 3 * 60 * 60,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            empty => {
                description => gettext('Include channels with empty PID'),
                default     => 'n',
                type        => 'confirm',
            },
            filterCA => {
                description => gettext('Filter channels, set all wanted CA(Common Access)'),
                # 0 for FTA, 1-4 for DVB Device, 32001 for AnalogPlugin
                type        => 'list',
                options     => 'multi',
                default     => '',
                choices     => sub{
                    my @knownCA;
                    foreach my $CA (@{$obj->{knownCA}}) {
                        my $desc;
                        if($CA eq '0')    { $desc = gettext("Free to air"); }
                        elsif($CA eq '1' 
                           or $CA eq '2' 
                           or $CA eq '3'  
                           or $CA eq '4') { $desc = sprintf(gettext("DVB card %s"),$CA);}
                        else              { $desc = sprintf("CA '%s'",$CA);      }
                        push(@knownCA,[$desc,$CA]);
                    }
                    return @knownCA;
                },
                check   => sub{
                    my $value = shift;
                    if(ref $value eq 'ARRAY') {
                        return join(',', @$value);
                    } else {
                        return $value;
                    }
                },
            },
            stripCH => {
                description => gettext("Clean channel names, only the 'long' part is visible."),
    			# Format in vdr 1.2.6 (Format "" or "long"). it show also all parts
    			# Format in vdr 1.3.10 (Format "short,long")
    			# Format in vdr 1.3.12 (Format "short,long;provider")
    			# Format in vdr 1.3.?? (Format "provider;short,long")
    			# Format in vdr 1.3.18 (Format "short,long;provider")
                default     => 'short,long;provider',
                type        => 'string',
            },
        },
        Commands => {
            cupdate => {
                description => gettext('Read channels and write them into database'),
                short       => 'cu',
                callback    => sub{ $obj->readData(@_) },
                DenyClass   => 'cedit',
                Level       => 'user',
            },
            clist => {
                description => gettext("List Channels from database 'cname'"),
                short       => 'cl',
                callback    => sub{ $obj->list(@_) },
                Level       => 'user',
            },
            cnew => {
                description => gettext("Create a new channel"),
                short       => 'cne',
                callback    => sub{ $obj->newChannel(@_) },
                Level       => 'user',
                DenyClass   => 'cedit',
            },
            cedit => {
                description => gettext("Edit a channel 'cid'"),
                short       => 'ced',
                callback    => sub{ $obj->editChannel(@_) },
                Level       => 'user',
                DenyClass   => 'cedit',
            },
            cdelete => {
                description => gettext("Delete one or more channels 'pos'"),
                short       => 'cdl',
                callback    => sub{ $obj->deleteChannel(@_) },
                Level       => 'user',
                DenyClass   => 'cedit',
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

    my $sql = "select count(*) from CHANNELS";
    my $gesamt = $obj->{dbh}->selectrow_arrayref($sql)->[0];

    $sql = "select count(*) from CHANNELGROUPS";
    my $groups = $obj->{dbh}->selectrow_arrayref($sql)->[0];

    return {
        message => sprintf(gettext('The system has %d saved Channels in %d Groups'), $gesamt, $groups),
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

    $self->{knownCA} = [0,1,2,3,4];

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize module');

    # Interval to read channels and put to DB
    Event->timer(
        interval => $self->{interval},
        prio => 6,  # -1 very hard ... 6 very low
        cb => sub{
            lg 'Start the interval reading channels to DB!';
            $self->readData();
        },
    );

	return $self;
}

# ------------------
sub _init {
# ------------------
    my $obj = shift || return error ('No Object!' );

    return 0, panic("Session to database is'nt connected")
      unless($obj->{dbh});

    # remove old table, if updated rows
    tableUpdated($obj->{dbh},'CHANNELS',16,1);
    tableUpdated($obj->{dbh},'CHANNELGROUPS',3,1);

    # Look for table or create this table
    my $version = main::getVersion;
    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS CHANNELS (
          Id varchar(100) NOT NULL,
          Name varchar(100) NOT NULL default '',
          Frequency int(11) NOT NULL default '0',
          Parameters varchar(100) default '',
          Source varchar(100),
          Srate int(11) default 0,
          VPID varchar(100) default '',
          APID varchar(100) default '',
          TPID varchar(100) default '',
          CA varchar(100) default '',
          SID int(11) default 0,
          NID int(11) default 0,
          TID int(11) default 0,
          RID int(11) default 0,
          GRP int(11) default 0,
          POS int(11) NOT NULL,
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    $obj->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS CHANNELGROUPS (
          Id int(11) auto_increment not NULL,
          Name varchar(100) default 'unknown',
          Counter int(11) default '0',
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Can't get modul SVDRP");
           return 0;
        }

        my $erg = $obj->readData();
        return 1;
    }, "CHANNELS: Read and register Channels ...", 5);
    return 1;
}

# ------------------
sub insert {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || return;
    my $pos = shift || return;
    my $grp = shift || 0;

    foreach my $CA (split(',', $data->[8])) {
        push(@{$obj->{knownCA}},$CA);
    }

    return if($obj->{empty} eq 'n' and not (($data->[6] ne "0" || $data->[7] ne "0"))); # Ignore Channels with APID = 0/TPID = 0 from PID Scan
    if($obj->{filterCA} ne "") {
       my $filter = $obj->{filterCA};
       $filter =~ s/\,/|/g; # Transform 0,2,400 => 0|2|400
       return 0 if(not ($data->[8] =~ /(^|\,)($filter)(\,|$)/s)); # check (^|,)(0|2|400)(,|$)
    }

	# Strip short and providername from channelname e.g ch
    if($obj->{stripCH}) {
		my $ch = $data->[0];
		my $filter = $obj->{stripCH};
		my @p = split(';',$filter);
		if(scalar @p == 2) {
			if(($p[0] =~ /provider/i)) { # format "provider;name"
				$ch = (split(';', $ch))[-1] if($ch =~ /;/);
				$filter = $p[1];
			}
			elsif(($p[1] =~ /provider/i)) { # format "name;provider"
				$ch = (split(';', $ch))[0] if($ch =~ /;/);
				$filter = $p[0];
			}
		}
		my @c = split(',',$filter);
		if(scalar @c == 2) {
			if(($c[0] =~ /long/i)) { # format "long,short"
				$ch = (split(',', $ch))[0] if($ch =~ /,/);
			}
			elsif(($c[1] =~ /long/i)) { # format "short,long"
				$ch = (split(',', $ch))[-1] if($ch =~ /,/);
			}
		}
	    $data->[0] = $ch if($ch);
	}

    # ID
    if ( $data->[3] eq 'C' or $data->[3] eq 'T') {
      while(length($data->[1]) > 3) {
  	    $data->[1] = substr($data->[1], 0, length($data->[1])-3);
      }
    }

    my $id;
    $data->[12] = (split(':', $data->[12]))[0];
#   if($data->[12] && $data->[12] > 0 && $data->[12] < 100) {
    # By DVB-C gabs Probleme weil die Zahl grösser 100 war
    # Siehe auch http://www.vdr-portal.de/board/thread.php?sid=&postid=364373
    if($data->[12] && $data->[12] > 0) {
        $id = sprintf('%s-%u-%u-%u-%u', $data->[3], $data->[10], ($data->[10] || $data->[11]) ? $data->[11] : $data->[1], $data->[9],$data->[12]);
    } else {
        $id = sprintf('%s-%u-%u-%u', $data->[3], $data->[10], ($data->[10] || $data->[11]) ? $data->[11] : $data->[1], $data->[9]);
    }
    unshift(@$data, $id);

    # ChannelGroup
    push(@$data, $grp);

    # POS
    push(@$data, $pos);

    my $sth = $obj->{dbh}->prepare('REPLACE INTO CHANNELS VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
    $sth->execute( @$data );
    lg sprintf('Add new Channel "%s" with Id "%s" in ChannelsDB!', $data->[1], $id);
    return 1;
}

# ------------------
sub insertGrp {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $pos = shift || return;
    my $name = shift || 0;

    lg sprintf('Add new ChannelGroup "%s" in ChannelsGroup!', $name);
    my $sth = $obj->{dbh}->prepare('INSERT INTO CHANNELGROUPS SET Name=?, Counter=?');
    $sth->execute($name, $pos)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    return $sth->{mysql_insertid};
}

# ------------------
sub readData {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $file = $obj->{file} || return 1, error ('No Channels File');

    return 1, panic ('No Channels File found') if( ! -e $file);

    # only if file modification from last read time
    my $mtime = (stat($file)->mtime);
    return
      if(! ref $console and defined $obj->{LastRefreshTime} and ($mtime > $obj->{LastRefreshTime}));

    $obj->{dbh}->do('DELETE FROM CHANNELS');
    $obj->{dbh}->do('DELETE FROM CHANNELGROUPS');

    my $fh = IO::File->new("< $file") or return error("Can't open File $file $! ");
    my $c = 0;
    my $nPos = 1;
    my $grp = 0;
    while ( defined (my $line = <$fh>) ) {
        $line =~ s/[\r|\n]//sig;
        next if($line eq "");
        my @data = split(':', $line, 13);
        $data[-1] = (split(':', $data[-1]))[0];

        if( $line =~ /^\:\@(\d*)\s*(.*)/ and $nPos <= $1) {
            $nPos = $1;
            my $grpText = $2;
            $grp = $obj->insertGrp($nPos, $grpText);
        } elsif( $line =~ /^\:(.+)/) {
            my $grpText = $1;
            $grp = $obj->insertGrp($nPos, $grpText);
        } else {
            $grp = $obj->insertGrp(1, gettext("Channels"))
                if(!$grp);
            $c++
                if(scalar @data > 4 && $obj->insert(\@data, $nPos++, $grp));
        }
    }
    $fh->close;

    # Cool we have new Channels!
    my $LastChannel = $obj->_LastChannel;
    if($obj->{LastChannel}->{POS} and $LastChannel->{POS} > $obj->{LastChannel}->{POS}) {
        $obj->_brandNewChannels($obj->{LastChannel}->{POS});
    }

    # Remember the maximum Channelposition
    $obj->{LastChannel} = $obj->_LastChannel;

    $console->message(sprintf(gettext("Write %d channels into database."), $c))
        if(ref $console);

    # sort list with CA numerical
    my %CA;
    @CA{@{$obj->{knownCA}}} = ();
    @{$obj->{knownCA}} = sort { if(is_numeric($a) && is_numeric($b)) {
                                    $a <=> $b
                                } else {
                                    $a cmp $b } } keys %CA;

    $obj->{LastRefreshTime} = $mtime;
    return 1;
}
# ------------------
sub getnum {
# ------------------
    use POSIX qw(strtod);
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    $! = 0;
    my($num, $unparsed) = strtod($str);
    if (($str eq '') || ($unparsed != 0) || $!) {
        return undef;
    } else {
        return $num;
    }
}
# ------------------
sub is_numeric { defined getnum($_[0]) }
# ------------------

# ------------------
sub list {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $id      = shift || '';
    my $params = shift;

    my $sql = qq|
select
    c.*, cg.Name as __GrpName
from
    CHANNELS as c,
    CHANNELGROUPS as cg
where
    c.Name like ?
    and
    c.GRP = cg.Id
|;

    my $fields = fields($obj->{dbh}, $sql);

    my $sortby = "POS";
    $sortby = $params->{sortby}
        if(exists $params->{sortby} && grep(/^$params->{sortby}$/i,@{$fields}));
    $sql .= "order by $sortby";
    $sql .= " desc"
        if(exists $params->{desc} && $params->{desc} == 1);


    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute('%'.$id.'%')
        or return error sprintf("Can't execute query: %s.",$sth->errstr);

    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);
    $console->table($erg,{sortable => 1 });
}


# ------------------
sub NameToChannel {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select Id from CHANNELS where UPPER(Name) = UPPER( ? )');
    $sth->execute($name)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Id} : undef;
}

# ------------------
sub PosToName {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $pos = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select Name from CHANNELS where POS = ?');
    $sth->execute($pos)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Name} : undef;
}

# ------------------
sub PosToChannel {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $pos = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select Id from CHANNELS where POS = ?');
    $sth->execute($pos)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Id} : undef;
}

# ------------------
sub ChannelGroupsArray {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('select %s, Id from CHANNELGROUPS %s order by Id', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelArray {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('select %s, POS from CHANNELS %s order by POS', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelIDArray {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('select %s, Id from CHANNELS %s order by POS', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelHash {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('select * from CHANNELS %s', $where);
    my $erg = $obj->{dbh}->selectall_hashref($sql, $field);
    return $erg;
}

# ------------------
sub ChannelToName {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select Name from CHANNELS where Id = ?');
    $sth->execute($id)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Name} : undef;
}

# ------------------
sub ChannelToPos {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('select POS from CHANNELS where Id = ?');
    $sth->execute($id)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{POS} : undef;
}


# ------------------
sub getChannelType {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $id = shift || return undef;
    my $pos = $obj->ChannelToPos($id);
    if($pos and $pos >= 1)
    {
      my $data = $obj->ChannelHash('POS', sprintf('POS = %d', $pos));
      if(exists $data->{$pos}) {
        my $ch = $data->{$pos};
        if($ch->{VPID}) {
          return 'TV';
        } elsif($ch->{APID}) {
          return 'RADIO';
        }
      }
    }
    error("Unknown channel! Can't identify type of channel with id: %s", $id);
    return 'UNKNOWN';
}

# ------------------
sub _LastChannel {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $sql = sprintf('select * from CHANNELS order by POS desc limit 1');
    my $erg = $obj->{dbh}->selectrow_hashref($sql);
    return $erg;
}

# ------------------
sub newChannel {
# ------------------
    my $self         = shift || return error ('No Object!' );
    my $watcher      = shift || return error ('No Watcher!');
    my $console      = shift || return error ('No Console');
    my $id           = shift || 0;
    my $defaultData  = shift || 0;

    $self->editChannel($watcher, $console, 0, $defaultData);
}

# ------------------
sub editChannel {
# ------------------
    my $self    = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $cid     = shift || 0;  # If channelid then edit channel
    my $data    = shift || 0;  # Data for defaults

    my $defaultData;
    if($cid and not ref $data) {

        $cid = $self->PosToChannel($cid)
            unless(index($cid, '-') > -1);

        my $sth = $self->{dbh}->prepare('select POS, Name, Frequency, Parameters, Source, Srate, VPID, APID, TPID, CA, SID, NID, TID, RID from CHANNELS where Id = ?');
            $sth->execute($cid)
            or return $console->err(sprintf(gettext("Channel '%s' does not exist in the database!"),$cid));
        $defaultData = $sth->fetchrow_hashref();
    } elsif (ref $data eq 'HASH') {
        $defaultData = $data;
    }

    my $questions = [
        'POS' => {
            typ     => 'hidden',
            def     => $defaultData->{POS} || 0,
        } ];

    my $newpos = [
        'NEWPOS' => {
            typ     => 'integer',
            msg     => gettext('Position'),
            def     => int($defaultData->{POS}),
            check   => sub{
                my $value = shift;
                if(int($value) > 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        } ];
    #Change Position only on editing
    push(@{$questions},@{$newpos})
        if($cid && main::getVdrVersion >= 10332);

    my $more = [
        'Name' => {
            typ     => 'string',
            def     => $defaultData->{Name} || gettext('New channel'),
            msg     => gettext("Name"),
            check   => sub{
                my $value = shift || return;
                if($value ne '') {
                    return $value;
                } else {
                    return undef, gettext('This is required!');
                }
            },
        },
        'Frequency' => {
            typ     => 'integer',
            msg     => gettext('Transponder frequency'),
            def     => int($defaultData->{Frequency}) || 0,
            check   => sub{
                my $value = shift;
                if(int($value) > 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'Source' => {
            typ     => 'string',
            def     => $defaultData->{Source} || "",
            msg     => gettext("Signal source"),
            check   => sub{
                my $value = shift || return;
                if($value ne '') {
                    return $value;
                } else {
                    return undef, gettext('This is required!');
                }
            },
        },
        'Parameters' => {
            typ     => 'string',
            def     => $defaultData->{Parameters} || "",
            msg     => gettext("Various parameters, depends on signal source"),
            check   => sub{
                my $value = shift || return;
                if($value ne '') {
                    return $value;
                } else {
                    return undef, gettext('This is required!');
                }
            },
        },
        'Srate' => {
            typ     => 'integer',
            msg     => gettext('Symbol rate'),
            def     => int($defaultData->{Srate}) || 27500,
            check   => sub{
                my $value = shift;
                if(int($value) > 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'VPID' => {
            typ     => 'integer',
            msg     => gettext('Video PID (VPID)'),
            def     => int($defaultData->{VPID}) || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'APID' => {
            typ     => 'string',
            def     => $defaultData->{APID} || 0,
            msg     => gettext("Audio PID (APID)"),
            check   => sub{
                my $value = shift || return;
                if($value ne '') {
                    return $value;
                } else {
                    return undef, gettext('This is required!');
                }
            },
        },
        'TPID' => {
            typ     => 'integer',
            msg     => gettext('Teletext PID (TPID)'),
            def     => int($defaultData->{TPID}) || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'CA' => {
            typ     => 'string',
            def     => $defaultData->{CA} || 0,
            msg     => gettext("Conditional access (CA)"),
            check   => sub{
                my $value = shift || return;
                if($value ne '') {
                    return $value;
                } else {
                    return undef, gettext('This is required!');
                }
            },
        },
        'SID' => {
            typ     => 'integer',
            msg     => gettext('Service ID (SID)'),
            def     => int($defaultData->{SID}) || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'NID' => {
            typ     => 'integer',
            msg     => gettext('Network ID (NID)'),
            def     => int($defaultData->{NID})  || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'TID' => {
            typ     => 'integer',
            msg     => gettext('Transport stream ID (TID)'),
            def     => int($defaultData->{TID})  || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
        'RID' => {
            typ     => 'integer',
            msg     => gettext('Radio ID (RID)'),
            def     => int($defaultData->{RID})  || 0,
            check   => sub{
                my $value = shift;
                if(int($value) >= 0) {
                    return int($value);
                } else {
                    return undef, gettext('No right Value!');
                }
            },
        },
    ];
    push(@{$questions},@{$more});

    # Ask Questions
    my $datasave = $console->question(($cid ? gettext('Edit channel')
                                            : gettext('New channel')), $questions, $data);

    if(ref $datasave eq 'HASH') {
        my $erg = $self->saveChannel($datasave, $datasave->{POS});

        my $error;
        foreach my $zeile (@$erg) {
            if($zeile =~ /^(\d{3})\s+(.+)/) {
                $error = $2 if(int($1) >= 500);
            }
        }
        unless($error) {
            debug sprintf('%s channel with name "%s" is saved%s',
                ($cid ? 'Changed' : 'New'),
                $data->{Name},
                ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
                );
                $console->message($erg);
        } else {
            error sprintf('%s channel with name "%s" does\'nt saved : %s',
                ($cid ? 'Changed' : 'New'),
                $data->{Name},
                $error
                );
                $console->err($erg);
        }
        sleep(1);
        $self->readData($watcher,$console);

        $console->redirect({url => $console->{browser}->{Referer}, wait => 2})
            if($console->typ eq 'HTML');
    }
}

# ------------------
sub saveChannel {
# ------------------
    my $self = shift || return error ('No Object!' );
    my $data = shift || return error('No Data to Save!');
    my $pos = shift || 0;

    my $erg;

    if($pos
       && defined $data->{NEWPOS}
       && $pos != $data->{NEWPOS} ) {
       $erg = $self->{svdrp}->command(
            sprintf("movc %s %s",
            $pos,
            $data->{NEWPOS}
       ));
       $pos = $data->{NEWPOS};
       push(@{$erg},"\r\n");
   }

    $erg = $self->{svdrp}->command(
        sprintf("%s %s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s",
            $pos ? "modc $pos" : "newc",
            $data->{Name},
            int($data->{Frequency}),
            $data->{Parameters},
            $data->{Source},
            int($data->{Srate}),
            int($data->{VPID}),
            $data->{APID},
            int($data->{TPID}),
            $data->{CA} ? $data->{CA} : '0',
            int($data->{SID}),
            int($data->{NID}),
            int($data->{TID}),
            int($data->{RID})
        )
    );
    return $erg;
}

# ------------------
sub deleteChannel {
# ------------------
    my $self = shift || return error ('No Object!' );
    my $watcher = shift;
    my $console = shift;
    my $channelid = shift || return $console->err(gettext("No channel to delete! Please use cdelete 'pos'"));
    my $answer  = shift || 0;

    my @channels  = reverse sort{ $a <=> $b } split(/[^0-9]/, $channelid);

    my $sql = sprintf('select Id,POS,Name from CHANNELS where POS in (%s)', join(',' => ('?') x @channels)); 
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@channels)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $data = $sth->fetchall_hashref('POS');

    foreach my $pos (@channels) {
        unless(exists $data->{$pos}) {
            $console->err(sprintf(gettext("Channel with number '%s' does not exist in database!"), $pos));
            next;
        }

        if(ref $console and $console->{TYP} ne 'HTML') {
            $console->table($data->{$pos});
            my $confirm = $console->confirm({
                typ   => 'confirm',
                def   => 'y',
                msg   => gettext('Are you sure to delete this channel?'),
            }, $answer);
            next if(! $answer eq 'y');
        }

        debug sprintf('Channel with name "%s" is deleted%s',
            $data->{$pos}->{Name},
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $self->{svdrp}->queue_cmds("delc $pos"); # Sammeln der Kommandos
    }

    if($self->{svdrp}->queue_cmds('COUNT')) {
        my $erg = $self->{svdrp}->queue_cmds("CALL"); # Aufrufen der Kommandos
        $console->msg($erg, $self->{svdrp}->err)
            if(ref $console);

        sleep(1);

        $self->readData($watcher,$console);

        $console->redirect({url => $console->{browser}->{Referer}, wait => 1})
            if(ref $console and $console->typ eq 'HTML');
    } else {
        $console->err(gettext("No channel to delete!"));
    }

    return 1;
}

# ------------------
sub _brandNewChannels {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $oldmaximumpos = shift || return;

    my $sql = 'select * from CHANNELS where POS > ?'; 
    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute($oldmaximumpos)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchall_hashref('POS');

    my $text;
    foreach my $chpos (sort {$erg->{$a} <=> $erg->{$b}} keys %$erg) {
        my $c = $erg->{$chpos};
        $text .= sprintf(gettext('New %s channel: %s on position: %d %s'),
            ($c->{VPID} > 5 or index('+', $c->{VPID})
                ? gettext('TV')
                : gettext('Radio')),
            $c->{Name},
            $c->{POS},
            (index('+', $c->{VPID}) || $c->{VPID} == 1 ? gettext('(encrypted)') : ''),
        );
    }

    my $rm = main::getModule('REPORT');
    $rm->news(
        sprintf(gettext('Discover %d new channels!'), scalar keys %$erg),
        $text,
        'clist',
        undef,
        'veryinteresting',
    );
    return 1;
}


1;
