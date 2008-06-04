package XXV::MODULES::CHANNELS;

use strict;

use Tools;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'CHANNELS',
        Prereq => {
#           'modul' => 'description',
        },
        Description => gettext('This module reads new channels and stores them in the database.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Status => sub{ $obj->status(@_) },
        Preferences => {
            interval => {
                description => gettext('How often channels are to be updated (in seconds)'),
                default     => 3 * 60 * 60,
                type        => 'integer',
                required    => gettext('This is required!'),
            },
            empty => {
                description => gettext('Insert channels with blank PID'),
                default     => 'n',
                type        => 'confirm',
            },
            filterCA => {
                description => gettext('Filter channel list, set all wanted CA (Common Access)'),
                # 0 for FTA, 1-4 for DVB Device, 32001 for AnalogPlugin
                type        => 'list',
                options     => 'multi',
                default     => '',
                choices     => sub{
                    my $knownCA;
                    foreach my $CA (@{$obj->{knownCA}}) {
                        my $desc;
                        if($CA eq '0')    { $desc = gettext("Free-to-air"); }
                        elsif($CA eq '1' 
                           or $CA eq '2' 
                           or $CA eq '3'  
                           or $CA eq '4') { $desc = sprintf(gettext("DVB card %s"),$CA);}
                        else              { $desc = sprintf("CA '%s'",$CA);      }
                        push(@{$knownCA},[$desc,$CA]);
                    }
                    return $knownCA;
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
                description => gettext("Cleans out channel names, only the 'long' part is visible."),
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
                description => gettext('Read channels and write them to the database'),
                short       => 'cu',
                callback    => sub{ $obj->readData(@_) },
                DenyClass   => 'cedit',
                Level       => 'user',
            },
            clist => {
                description => gettext("List channels from database 'cname'"),
                short       => 'cl',
                callback    => sub{ $obj->list(@_) },
                Level       => 'user',
            },
            cnew => {
                description => gettext("Create new channel"),
                short       => 'cne',
                callback    => sub{ $obj->newChannel(@_) },
                Level       => 'user',
                DenyClass   => 'cedit',
            },
            cedit => {
                description => gettext("Edits a channel 'cid'"),
                short       => 'ced',
                callback    => sub{ $obj->editChannel(@_) },
                Level       => 'user',
                DenyClass   => 'cedit',
            },
            cdelete => {
                description => gettext("Deletes one or more channels 'pos'"),
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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $lastReportTime = shift || 0;

    my $sql = "SELECT SQL_CACHE count(*) from CHANNELS";
    my $gesamt = $obj->{dbh}->selectrow_arrayref($sql)->[0];

    $sql = "SELECT SQL_CACHE count(*) from CHANNELGROUPS";
    my $groups = $obj->{dbh}->selectrow_arrayref($sql)->[0];

    return {
        message => sprintf(gettext('The system has saved %d channels from %d groups'), $gesamt, $groups),
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
    my $obj = shift || return error('No object defined!');

    unless($obj->{dbh}) {
      panic("Session to database is'nt connected");
      return 0;
    }

    my $version = 27; # Must be increment if rows of table changed
    # this tables hasen't handmade user data,
    # therefore old table could dropped if updated rows
    if(!tableUpdated($obj->{dbh},'CHANNELS',$version,1)) {
        return 0;
    }
    if(!tableUpdated($obj->{dbh},'CHANNELGROUPS',$version,1)) {
        return 0;
    }

    # Look for table or create this table
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
          Id int(11) not NULL,
          Name varchar(100) default 'unknown',
          PRIMARY KEY  (Id)
        ) COMMENT = '$version'
    |);

    main::after(sub{
        $obj->{svdrp} = main::getModule('SVDRP');
        unless($obj->{svdrp}) {
           panic ("Couldn't get modul SVDRP");
           return 0;
        }

        return $obj->readData();
    }, "CHANNELS: Read and register channels ...", 5);
    return 1;
}

# ------------------
sub _prepare {
# ------------------
    my $obj = shift || return error('No object defined!');
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
    my $freqID = $data->[1];
    if ( $data->[3] eq 'C' or $data->[3] eq 'T') {
      while(length($freqID) > 3) {
  	    $freqID = substr($freqID, 0, length($freqID)-3);
      }
    }

    my $id;
    $data->[12] = (split(':', $data->[12]))[0];
#   if($data->[12] && $data->[12] > 0 && $data->[12] < 100) {
    # By DVB-C gabs Probleme weil die Zahl grösser 100 war
    # Siehe auch http://www.vdr-portal.de/board/thread.php?sid=&postid=364373
    if($data->[12] && $data->[12] > 0) {
        $id = sprintf('%s-%u-%u-%u-%u', $data->[3], $data->[10], ($data->[10] || $data->[11]) ? $data->[11] : $freqID, $data->[9],$data->[12]);
    } else {
        $id = sprintf('%s-%u-%u-%u', $data->[3], $data->[10], ($data->[10] || $data->[11]) ? $data->[11] : $freqID, $data->[9]);
    }

    my $attr = {
          Id => $id,
          Name => $data->[0],
          Frequency => $data->[1],
          Parameters => $data->[2],
          Source => $data->[3],
          Srate => $data->[4],
          VPID => $data->[5],
          APID => $data->[6],
          TPID => $data->[7],
          CA => $data->[8],
          SID => $data->[9],
          NID => $data->[10],
          TID => $data->[11],
          RID => $data->[12],
          GRP => $grp,
          POS => $pos
    };
    return $attr;
}

# ------------------
sub _replace {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $attr = shift || return error('No data defined!');

    my $sth = $obj->{dbh}->prepare('REPLACE INTO CHANNELS(Id,Name,Frequency,Parameters,Source,Srate,VPID,APID,TPID,CA,SID,NID,TID,RID,GRP,POS) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
    return $sth->execute(
        $attr->{Id},
        $attr->{Name},
        $attr->{Frequency},
        $attr->{Parameters},
        $attr->{Source},
        $attr->{Srate},
        $attr->{VPID},
        $attr->{APID},
        $attr->{TPID},
        $attr->{CA},
        $attr->{SID},
        $attr->{NID},
        $attr->{TID},
        $attr->{RID},
        $attr->{GRP},
        $attr->{POS}
    );
}

# ------------------
sub insertGrp {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $pos = shift || return;
    my $name = shift || 0;

    lg sprintf('Update group of channels "%s" (%d).', $name, $pos);
    my $sth = $obj->{dbh}->prepare('REPLACE INTO CHANNELGROUPS SET Name=?, Id=?');
    $sth->execute($name, $pos)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    return $pos;
}

# ------------------
sub readData {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;

    # Read channels over SVDRP
    my $lstc = $obj->{svdrp}->command('lstc :groups');
    my $vdrData = [ grep(/^250/, @$lstc) ];

    unless(scalar @$vdrData) {
        # Delete old Records
        $obj->{dbh}->do('DELETE FROM CHANNELS');
        $obj->{dbh}->do('DELETE FROM CHANNELGROUPS');

        my $msg = gettext('No channels available!');
        con_err($console,$msg);
        return;
    }

    my $nPos = 1;
    my $grp = 0;
    my $channelText;
    my $grpText;
    my $newChannels;
    my $changedData = 0;
    my $updatedData = 0;
    my $deleteData = 0;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE * from CHANNELS');
    $sth->execute()
      or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $db_data = $sth->fetchall_hashref('Id');

    my $gsth = $obj->{dbh}->prepare('SELECT SQL_CACHE * from CHANNELGROUPS');
    $gsth->execute()
      or return error sprintf("Couldn't execute query: %s.",$gsth->errstr);
    my $grp_data = $gsth->fetchall_hashref('Id');

    lg sprintf("Compare channels database with data from vdr : %d / %d", (scalar keys %$db_data) + (scalar keys %$grp_data) ,scalar @$vdrData);
  
    foreach my $line (@{$vdrData}) {

      next if($line eq "");

      if($line =~ /250[\-|\s]0\s/) { # Channels groups
        ($nPos, $grpText) = $line =~ /^250[\-|\s]0\s\:\@(\d+)\s(.+)/si;
        if(exists $grp_data->{$nPos}) {
          if($grp_data->{$nPos}->{Name} ne $grpText) {
            $grp = $obj->insertGrp($nPos, $grpText);
          } else {
            $grp = $nPos;
          }
          delete $grp_data->{$nPos};
        } else {
            $grp = $obj->insertGrp($nPos, $grpText);
        }
      } else {
          # Insert first group
          unless($grp) {
            $grp = 1;
            if(exists $grp_data->{$grp}) {
              $grpText = gettext("Channels");
              if($grp_data->{$nPos}->{Name} ne $grpText) {
                $obj->insertGrp($grp, $grpText);
              }
              delete $grp_data->{$nPos};
            } else {
              $obj->insertGrp($grp, $grpText);
            }
          }

          ($nPos, $channelText) = $line =~ /^250[\-|\s](\d+)\s(.+)/si;

          my @data = split(':', $channelText, 13);
          $data[-1] = (split(':', $data[-1]))[0];

          if(scalar @data > 4) {
            my $row = $obj->_prepare(\@data, $nPos++, $grp);
            next unless($row);

            my $id = $row->{Id};

            # Exists in DB .. update
            if(exists $db_data->{$id}) {
              # Compare fields
              foreach my $field (qw/Name Frequency Parameters Source Srate VPID APID TPID CA SID NID TID RID GRP POS/) {
                next if(not exists $row->{$field} or not $row->{$field});
                if((not exists $db_data->{$id}->{$field})
                    or (not $db_data->{$id}->{$field})
                    or ($db_data->{$id}->{$field} ne $row->{$field})) {
                  lg sprintf('Update channel "%s" - %s.', $row->{Name}, $id);
                  $obj->_replace($row);
                  $updatedData++;
                  last;
                }
              }

              # delete updated rows from hash
              delete $db_data->{$id};

            } else {
              # Not exists in DB .. insert
              lg sprintf('Add new channel "%s" - %s.', $row->{Name}, $id);
              $obj->_replace($row);
              $changedData++;
              # Remember new channels
              $newChannels->{$id} = $row;
            }
          }
      }
    }

    # Delete unused entrys in DB 
    if(scalar keys %$db_data > 0) {
      my @todel = keys(%$db_data);
      my $sql = sprintf('DELETE FROM CHANNELS WHERE Id IN (%s)', join(',' => ('?') x @todel)); 
      my $sth = $obj->{dbh}->prepare($sql);
      if(!$sth->execute(@todel)) {
          error sprintf("Couldn't execute query: %s.",$sth->errstr);
      }
      $deleteData += scalar @todel;
    }

    # Delete unused entrys in DB 
    if(scalar keys %$grp_data > 0) {
      my @todel = keys(%$grp_data);
      my $sql = sprintf('DELETE FROM CHANNELGROUPS WHERE Id IN (%s)', join(',' => ('?') x @todel)); 
      my $sth = $obj->{dbh}->prepare($sql);
      if(!$sth->execute(@todel)) {
          error sprintf("Couldn't execute query: %s.",$sth->errstr);
      }
      #$deleteData += scalar @todel;
    }

    # sort list with CA numerical
    my %CA;
    @CA{@{$obj->{knownCA}}} = ();
    @{$obj->{knownCA}} = sort { if(is_numeric($a) && is_numeric($b)) {
                                    $a <=> $b
                                } else {
                                    $a cmp $b } } keys %CA;

    $obj->_brandNewChannels($newChannels) if($newChannels);

    con_msg($console, sprintf(gettext("There are %d channels inserted, %d channels updated, %d channels deleted into database."), $changedData, $updatedData, $deleteData));

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
    my $obj = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id      = shift || '';
    my $params = shift;

    my %f = (
        'Id' => gettext('Service'),
        'Name' => gettext('Name'),
        'Frequency' => gettext('Transponder frequency'),
        'Parameters' => gettext('Parameters'),
        'Source' => gettext('Signal source'),
        'Srate' => gettext('Symbol rate'),
        'VPID' => gettext('Video PID'),
        'APID' => gettext('Audio PID'),
        'TPID' => gettext('Teletext PID'),
        'CA' => gettext('Conditional access'),
        'SID' => gettext('SID'),
        'TID' => gettext('TID'),
        'NID' => gettext('NID'),
        'RID' => gettext('RID'),
        'GRP' => gettext('Channel group'),
        'POS' => gettext('Position'),
    );

    my $sql = qq|
SELECT SQL_CACHE 
    c.Id as \'$f{'Id'}\',
    c.Name as \'$f{'Name'}\',
    c.Frequency as \'$f{'Frequency'}\',
    c.Parameters as \'$f{'Parameters'}\',
    c.Source as \'$f{'Source'}\',
    c.Srate as \'$f{'Srate'}\',
    c.VPID as \'$f{'VPID'}\',
    c.APID as \'$f{'APID'}\',
    c.TPID as \'$f{'TPID'}\',
    c.CA as \'$f{'CA'}\',
    c.SID as \'$f{'SID'}\',
    c.NID as \'$f{'NID'}\',
    c.TID as \'$f{'TID'}\',
    c.RID as \'$f{'RID'}\',
    c.GRP as \'$f{'GRP'}\',
    c.POS as \'$f{'POS'}\',
    cg.Name as __GrpName
from
    CHANNELS as c,
    CHANNELGROUPS as cg
WHERE
    c.Name LIKE ?
    AND c.GRP = cg.Id
ORDER BY
|;

    my $sortby = "POS";
    if(exists $params->{sortby}) {
      while(my($k, $v) = each(%f)) {
        if($params->{sortby} eq $k or $params->{sortby} eq $v) {
          $sortby = $k;
          last;
        }
      }
    }
    $sql .= $sortby;
    $sql .= " desc"
        if(exists $params->{desc} && $params->{desc} == 1);

    my $rows;
    my $limit = $console->{cgi} && $console->{cgi}->param('limit') ? CORE::int($console->{cgi}->param('limit')) : 0;
    if($limit > 0) {
      # Query total count of rows
      my $rsth = $obj->{dbh}->prepare($sql);
        $rsth->execute('%'.$id.'%')
          or return error sprintf("Couldn't execute query: %s.",$rsth->errstr);
      $rows = $rsth->rows;

      # Add limit query
      if($console->{cgi}->param('start')) {
        $sql .= " LIMIT " . CORE::int($console->{cgi}->param('start'));
        $sql .= "," . $limit;
      } else {
        $sql .= " LIMIT " . $limit;
      }
    }

    my $sth = $obj->{dbh}->prepare($sql);
    $sth->execute('%'.$id.'%')
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    $rows = $sth->rows unless($rows);

    my $fields = $sth->{'NAME'};
    my $erg = $sth->fetchall_arrayref();
    unless($console->typ eq 'AJAX') {
      unshift(@$erg, $fields);
    }

    $console->table($erg, {
        sortable => 1,
        rows => $rows
    });
}


# ------------------
sub NameToChannel {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $name = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE Id from CHANNELS where UPPER(Name) = UPPER( ? )');
    $sth->execute($name)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Id} : undef;
}

# ------------------
sub PosToName {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $pos = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE Name from CHANNELS where POS = ?');
    $sth->execute($pos)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Name} : undef;
}

# ------------------
sub PosToChannel {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $pos = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE Id from CHANNELS where POS = ?');
    $sth->execute($pos)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Id} : undef;
}

# ------------------
sub ChannelGroupsArray {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('SELECT SQL_CACHE %s, Id from CHANNELGROUPS %s order by Id', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelArray {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('SELECT SQL_CACHE %s, POS from CHANNELS %s order by POS', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelWithGroup {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf(q|SELECT SQL_CACHE %s, ( SELECT 
        g.Name FROM CHANNELGROUPS as g WHERE c.GRP = g.Id
        LIMIT 1) as GRP from CHANNELS as c %s order by c.POS|, $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelIDArray {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('SELECT SQL_CACHE %s, Id from CHANNELS %s order by POS', $field, $where);
    my $erg = $obj->{dbh}->selectall_arrayref($sql);
    return $erg;
}

# ------------------
sub ChannelHash {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $field = shift || return undef;
    my $where = shift || '';
    $where = sprintf('WHERE %s', $where) if($where);

    my $sql = sprintf('SELECT SQL_CACHE * from CHANNELS %s', $where);
    my $erg = $obj->{dbh}->selectall_hashref($sql, $field);
    return $erg;
}

# ------------------
sub ChannelToName {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE Name from CHANNELS where Id = ?');
    $sth->execute($id)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{Name} : undef;
}

# ------------------
sub ChannelToPos {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE POS from CHANNELS where Id = ?');
    $sth->execute($id)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    return $erg ? $erg->{POS} : undef;
}

# ------------------
sub ToCID {
# ------------------
  my $obj = shift || return error('No object defined!');
  my $text = shift || return undef;

  if($text =~ /^\d+$/ and (my $pch = $obj->PosToChannel($text) )) {
    return $pch;
  } elsif((my $nch = $obj->NameToChannel($text) )) {
    return $nch;
  } elsif(my $name = $obj->ChannelToName($text)) {
    return $text;
  }
  return undef;
}
# ------------------
sub getChannelType {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $id = shift || return undef;

    my $sth = $obj->{dbh}->prepare('SELECT SQL_CACHE VPID,APID from CHANNELS where Id = ?');
    $sth->execute($id)
        or return error sprintf("Couldn't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchrow_hashref();
    if($erg) {
        if(exists $erg->{VPID}) {
          return 'TV';
        } elsif(exists $erg->{APID}) {
          return 'RADIO';
        }
    }
    error sprintf("Unknown channel! Couldn't identify type of channel with id: %s", $id);
    return 'UNKNOWN';
}

# ------------------
sub newChannel {
# ------------------
    my $self         = shift || return error('No object defined!');
    my $watcher      = shift || return error('No watcher defined!');
    my $console      = shift || return error('No console defined!');
    my $id           = shift || 0;
    my $defaultData  = shift || 0;

    $self->editChannel($watcher, $console, 0, $defaultData);
}

# ------------------
sub editChannel {
# ------------------
    my $self    = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $cid     = shift || 0;  # If channelid then edit channel
    my $data    = shift || 0;  # Data for defaults

    my $defaultData;
    if($cid and not ref $data) {

        $cid = $self->PosToChannel($cid)
            unless(index($cid, '-') > -1);

        my $sth = $self->{dbh}->prepare('SELECT SQL_CACHE POS, Name, Frequency, Parameters, Source, Srate, VPID, APID, TPID, CA, SID, NID, TID, RID from CHANNELS where Id = ?');
            $sth->execute($cid)
            or return con_err($console, sprintf(gettext("Channel '%s' does not exist in the database!"),$cid));
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
                    return undef, gettext('Value incorrect!');
                }
            },
        } ];
    #Change Position only on editing
    push(@{$questions},@{$newpos})
        if($cid);

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
                    return undef, gettext('Value incorrect!');
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
            msg     => gettext("Various parameters, depending on signal source"),
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                    return undef, gettext('Value incorrect!');
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
                con_err($console, $erg);
        }
        sleep(1);
        $self->readData($watcher,$console);

        $console->redirect({url => '?cmd=clist', wait => 1})
            if($console->typ eq 'HTML');
    }
}

# ------------------
sub saveChannel {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || return error('No data defined!');
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
    my $self = shift || return error('No object defined!');
    my $watcher = shift;
    my $console = shift;
    my $channelid = shift || return con_err($console, gettext("No channel defined for deletion! Please use cdelete 'pos'!"));
    my $answer  = shift || 0;

    my @channels  = reverse sort{ $a <=> $b } split(/[^0-9]/, $channelid);

    my $sql = sprintf('SELECT SQL_CACHE Id,POS,Name from CHANNELS where POS in (%s)', join(',' => ('?') x @channels)); 
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@channels)
        or return con_err($console, sprintf("Couldn't execute query: %s.",$sth->errstr));
    my $data = $sth->fetchall_hashref('POS');

    foreach my $pos (@channels) {
        unless(exists $data->{$pos}) {
            con_err($console, sprintf(gettext("Channel '%s' does not exist in the database!"), $pos));
            next;
        }

        if(ref $console and $console->{TYP} ne 'HTML') {
            $console->table($data->{$pos});
            my $confirm = $console->confirm({
                typ   => 'confirm',
                def   => 'y',
                msg   => gettext('Would you like to delete this channel?'),
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

        $console->redirect({url => '?cmd=clist', wait => 1})
            if(ref $console and $console->typ eq 'HTML' and !$self->{svdrp}->err);
    } else {
        con_err($console, gettext("No channel defined for deletion!"));
    }

    return 1;
}

# ------------------
sub _brandNewChannels {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $attr = shift || return;

    my @lines;
    foreach my $id (keys %$attr) {
        my $c = $attr->{$id};
        push(@lines, sprintf(gettext('New %s channel: %s on position: %d %s'),
            ($c->{VPID}
                ? gettext('TV')
                : gettext('Radio')),
            $c->{Name},
            $c->{POS},
            (($c->{CA} && (!is_numeric($c->{CA}) || $c->{CA} > 16)) ? gettext('(encrypted)') : ''),
        ));
        last if(25 < scalar @lines );
    }

    my $rm = main::getModule('REPORT');
    $rm->news(
        sprintf(gettext('Found %d new channels!'), scalar keys %$attr),
        join('\r\n',@lines),
        'clist',
        undef,
        'veryinteresting',
    );
    return 1;
}


1;
