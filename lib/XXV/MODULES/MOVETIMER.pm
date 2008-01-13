package XXV::MODULES::MOVETIMER;

use strict;
use Tools;
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
  my $self = shift || return error('No object defined!');
  my $args = {
      Name => 'MOVETIMER',
      Prereq => {
          # 'Perl::Module' => 'Description',
      },
      Description => gettext('This modul move timers between channels.'),
      Version => (split(/ /, '$Revision$'))[1],
      Date => (split(/ /, '$Date$'))[1],
      Author => 'Andreas Brachold',
      LastAuthor => (split(/ /, '$Author$'))[1],
      Preferences => {
          active => {
              description => gettext('Activate this service'),
              default     => 'n',
              type        => 'confirm',
              required    => gettext('This is required!'),
          },
      },
      Commands => {
          movetimer => {
              description => gettext("Manual move timer between channels"),
              short       => 'mt',
              callback    => sub{ $self->movetimermanual(@_) },
              Level       => 'user',
              DenyClass   => 'tedit',
          },
          movetimerlist => {
              description => gettext("List rules to move timer between channels"),
              short       => 'mtl',
              callback    => sub{ $self->movetimerlist(@_) },
              Level       => 'user',
              DenyClass   => 'tedit',
          },
          movetimercreate => {
              description => gettext("Create rule to move timer between channels"),
              short       => 'mtc',
              callback    => sub{ $self->movetimercreate(@_) },
              Level       => 'user',
              DenyClass   => 'tedit',
          },
          movetimerdelete => {
              description => gettext("Delete rule to move timer between channels"),
              short       => 'mtd',
              callback    => sub{ $self->movetimerdelete(@_) },
              Level       => 'user',
              DenyClass   => 'tedit',
          },
          movetimeredit => {
              description => gettext("Edit rule to move timer between channels"),
              short       => 'mte',
              callback    => sub{ $self->movetimeredit(@_) },
              Level       => 'user',
              DenyClass   => 'tedit',
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

  # run as background process
  #$self->{background} = delete $attr{'-background'};

  # The Initprocess
  my $erg = $self->_init or return error('Problem to initialize modul!');

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

    my $version = main::getDBVersion();
    if(!tableUpdated($self->{dbh},'MOVETIMER',$version,0)) {
      return 0;
    }

    # Look for table or create this table
    $self->{dbh}->do(qq|
      CREATE TABLE IF NOT EXISTS MOVETIMER (
          id int unsigned auto_increment NOT NULL,
          source varchar(64) NOT NULL,
          destination varchar(64) NOT NULL,
          move  enum('y', 'n', 'collision') default 'collision',
          original   enum('move', 'keep', 'copy') default 'move',
          PRIMARY KEY (id),
          UNIQUE KEY (source) 
        ) COMMENT = '$version'
    |);

    main::after(sub{

        $self->{svdrp} = main::getModule('SVDRP');
        unless($self->{svdrp}) {
           panic ("Couldn't get modul SVDRP");
           return 0;
        }

        my $m = main::getModule('TIMERS');
        $m->updated(sub{
        return 0 if($self->{active} ne 'y');

        lg 'Start timer callback to move timer!';
        return $self->_movetimer();

        });
        return 1;
    }, "MOVETIMER: Install callback at move timer ...", 95);

    return 1;
}

# ------------------
sub movetimermanual {
# ------------------
  my $self = shift || return error('No object defined!');
  my $watcher = shift;
  my $console = shift;
  my $id = shift;

  return 0 unless($self->_movetimer($watcher,$console,$id));

  $console->redirect({url => '?cmd=movetimerlist', wait => 1})
    if($console->typ eq 'HTML');

  return 1;
}

# ------------------
sub _movetimer {
# ------------------
  my $self = shift || return error('No object defined!');
  my $watcher = shift;
  my $console = shift;
  my $id = shift;

  my $modT = main::getModule('TIMERS') || return;

  my $sth = $self->{dbh}->prepare(
q|
  select
  t.Id as Id,
  IF(t.Status & 1,'y','n') as Activ,
  IF(t.Status & 4,'y','n') as VPS,
  t.Status as Status,
  t.ChannelID as ChannelID,
  t.File as File,
  t.aux as aux,
  t.Day as Day,
  t.Start as Start,
  t.Stop as Stop,
  t.Priority as Priority,
  t.Lifetime as Lifetime,
  t.Collision as Collision,
  IF(t.Status & 1 and NOW() between t.NextStartTime and t.NextStopTime,1,0) as Running 
  from TIMERS as t,MOVETIMER as m 
  where 
  m.source = t.channelid
  and m.move != 'm'
  and t.Status & 1
|);

  if(!$sth->execute()) {
      return error sprintf("Couldn't execute query: %s.",$sth->errstr);
  }
  my $timer = $sth->fetchall_hashref('Id');
  return unless($timer);

  $sth = $self->{dbh}->prepare("select * from MOVETIMER where move != 'n'");
  if(!$sth->execute()) {
        error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $console->err(sprintf(gettext("Couldn't query rules to move timer from database!")))
          if($console);
  }
  my $rules = $sth->fetchall_hashref('id');
  return unless($rules);

  my $bChange = 0;
  foreach my $tid (keys %$timer) {

    my $data = $timer->{$tid};

    foreach my $id (sort keys %$rules) {

      my $rule = $rules->{$id};

      if($data->{ChannelID} eq $rule->{source}) {

        # Move timer if collision present
        if($rule->{move} eq 'collision') {
          # None Collision present
          last unless($data->{Collision});
          # Search maximum priority of collision
          my $maxPrio = 1;
          foreach my $tc (split(',', $data->{Collision})) {
            my $col = (split(':', $tc))[1];
            $maxPrio = $col
              if($col > $maxPrio);
          }
          # dont solve collision until lesser own Priority
          last if($maxPrio < $data->{Priority});
        }

        debug sprintf("Move timer %d (%s) at %s : from %s to %s", 
                      $data->{Id}, 
                      $data->{File}, 
                      $data->{Day}, 
                      $rule->{source},
                      $rule->{destination});

        if($rule->{original} eq 'keep' ) {

          # Keep original timer but disable him
          $data->{Activ} = 'n';
          $self->modifyTimer($data,$tid);

          # Create new timer
          $data->{Activ} = 'y';
          $data->{ChannelID} = $rule->{destination};
          $self->modifyTimer($data,0);

        } elsif($rule->{original} eq 'copy' ) {

          # Copy to new timer
          $data->{Activ} = 'y';
          $data->{ChannelID} = $rule->{destination};
          $self->modifyTimer($data,0);

        } else {

          # Edit timer direct
          $data->{ChannelID} = $rule->{destination};
          $self->modifyTimer($data,$tid);

        }

        last;
      }
    }
  }
  if($self->{svdrp}->queue_cmds('COUNT')) {
      my $erg = $self->{svdrp}->queue_cmds("CALL"); # deqeue commands
      $console->msg($erg, $self->{svdrp}->err)
          if(ref $console);

    $modT->readData($watcher, $console)
  } else {
    $console->msg(gettext("There none timer to move."))
        if(ref $console);
  }
  return 1;
}


# ------------------
sub modifyTimer {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || return error('No data defined!');
    my $id = shift || 0;

    my $status = ($data->{Activ} eq 'y' ? 1 : 0);
       $status |= ($data->{VPS} eq 'y' ? 4 : 0);

    $data->{File} =~ s/:/|/g;
    $data->{File} =~ s/(\r|\n)//sig;

    $self->{svdrp}->queue_cmds(
        sprintf("%s %s:%s:%s:%s:%s:%s:%s:%s:%s",
            $id ? "modt $id" : "newt",
            $status,
            $data->{ChannelID},
            $data->{Day},
            $data->{Start},
            $data->{Stop},
            int($data->{Priority}),
            int($data->{Lifetime}),
            $data->{File},
            ($data->{aux} || '')
        )
    );
}

# ------------------
# Name:  movetimercreate
# Descr: create rule to move timer.
# Usage: $self->movetimercreate($watcher, $console, [$userdata]);
# ------------------
sub movetimercreate {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id = shift || 0;
    my $data    = shift || 0;

    $self->movetimeredit($watcher, $console, $id, $data);
}

# ------------------
# Name:  movetimeredit
# Descr: edit rule to move timer.
# Usage: $self->movetimeredit($watcher, $console, [$id], [$userdata]);
# ------------------
sub movetimeredit {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id = shift || 0;
    my $data    = shift || 0;

    my $modC = main::getModule('CHANNELS');

    my $rule;
    if($id and not ref $data) {
        my $sth = $self->{dbh}->prepare("select * from MOVETIMER where id = ?");
        $sth->execute($id)
            or return $console->err(sprintf(gettext("Rule to move timer with ID '%s' does not exist in the database!"),$id));
        $rule = $sth->fetchrow_hashref();

    } elsif (ref $data eq 'HASH') {
        $rule = $data;
    }

    my $con = $console->typ eq "CONSOLE";
    my $questions = [
        'id' => {
            typ     => 'hidden',
            def     => $rule->{id} || 0,
        },
        'source' => {
            typ     => 'list',
            def     => $con ? $modC->ChannelToPos($rule->{source}) : $rule->{source},
            choices => $con ? $modC->ChannelArray('Name') : $modC->ChannelIDArray('Name'),
            msg     => gettext('Which channel should used as source?'),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift || return;

                if(my $name = $modC->ChannelToName($value)) {
                    $data->{source} = $value;
                    return $value;
                } elsif(my $ch = $modC->PosToChannel($value) || $modC->NameToChannel($value) ) {
                    $data->{source} = $value;
                    return $ch;
                } elsif( ! $modC->NameToChannel($value)) {
                    return undef, sprintf(gettext("This channel '%s' does not exist!"),$value);
                } else {
                   return undef, gettext("This is required!");
                }
            },
        },
        'destination' => {
            typ     => 'list',
            def     => $con ? $modC->ChannelToPos($rule->{destination}) : $rule->{destination},
            choices => $con ? $modC->ChannelArray('Name') : $modC->ChannelIDArray('Name'),
            msg     => gettext('Which channel should used as destination?'),
            req     => gettext("This is required!"),
            check   => sub{
                my $value = shift || return;

                if(my $name = $modC->ChannelToName($value)) {
                    $data->{destination} = $value;
                    return $value;
                } elsif(my $ch = $modC->PosToChannel($value) || $modC->NameToChannel($value) ) {
                    $data->{destination} = $value;
                    return $ch;
                } elsif( ! $modC->NameToChannel($value)) {
                    return undef, sprintf(gettext("This channel '%s' does not exist!"),$value);
                } else {
                   return undef, gettext("This is required!");
                }
            },
        },
        'move' => {
            msg => gettext('When should use this rule'),
            def => $rule->{move} || 'collision',
            typ => 'list',
            choices     => sub {
                                my $erg = $self->_move_rules();
                                map { my $x = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $x; } @$erg;
                                return @$erg;
                              },
        },
        'original' => {
            msg => gettext('How should timer handled, if changed'),
            def => $rule->{original} || 'move',
            typ => 'list',
            choices     => sub {
                                my $erg = $self->_original_timer_rules();
                                map { my $x = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $x; } @$erg;
                                return @$erg;
                              },
        },
    ];

    # Ask Questions
    $data = $console->question(($id ? gettext('Edit rule to move timer')
					 : gettext('Create a new rule to move timer')), $questions, $data);

    if(ref $data eq 'HASH') {
    	$self->_insert($console, $data);

    	$data->{id} = $self->{dbh}->selectrow_arrayref('SELECT max(id)+1 FROM MOVETIMER')->[0]
    		if(not $data->{id});

        $console->message(gettext('Rule to move timer saved!'));
        debug sprintf('%s rule to move timer is saved%s',
            ($id ? 'New' : 'Changed'),
            ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
            );

        $self->_movetimer($watcher, $console, $data->{id});

        $console->redirect({url => '?cmd=movetimerlist', wait => 1})
          if($console->typ eq 'HTML');
    }
    return 1;
}

# ------------------
sub _insert {
# ------------------
    my $self = shift || return error('No object defined!');
    my $console = shift || return error('No console defined!');
    my $data = shift || return;

    my $sth;
    if(ref $data eq 'HASH') {
        my ($names, $vals, $kenn);
        map {
            push(@$names, $_);
            push(@$vals, $data->{$_}),
            push(@$kenn, '?'),
        } sort keys %$data;

        my $sql = sprintf("REPLACE INTO MOVETIMER (%s) VALUES (%s)",
                join(', ', @$names),
                join(', ', @$kenn),
        );
        $sth = $self->{dbh}->prepare( $sql );
        if(!$sth->execute(@$vals)) {
          error sprintf("Couldn't execute query: %s.",$sth->errstr);
          $console->err(sprintf(gettext("Couldn't insert rule move timer in database!")));
          return 0;
        }
    } else {
        $sth = $self->{dbh}->prepare('REPLACE INTO MOVETIMER VALUES (?,?,?,?,?)');
        if(!$sth->execute(@$data)) {
          error sprintf("Couldn't execute query: %s.",$sth->errstr);
          $console->err(sprintf(gettext("Couldn't insert rule move timer in database!")));
          return 0;
        }
    }
    return 1;  
}

# ------------------
# Name:  movetimerdelete
# Descr: Routine to delete move timer rule.
# Usage: $self->movetimerdelete($watcher, $console, $id);
# ------------------
sub movetimerdelete {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');
    my $id = shift || return $console->err(gettext("Missing ID to select rules for deletion! Please use movetimerdelete 'id'")); 

    my @rules  = reverse sort{ $a <=> $b } split(/[^0-9]/, $id);

    my $sql = sprintf('DELETE FROM MOVETIMER where id in (%s)', join(',' => ('?') x @rules)); 
    my $sth = $self->{dbh}->prepare($sql);
    if(!$sth->execute(@rules)) {
        error sprintf("Couldn't execute query: %s.",$sth->errstr);
        $console->err(sprintf(gettext("Rule to move timer with ID '%s' does not exist in the database!"),$id));
        return 0;
    }

    $console->message(sprintf gettext("Rule to move timer %s is deleted."), join(',', @rules));
    debug sprintf('Rule to move timer with id "%s" is deleted%s',
        join(',', @rules),
        ( $console->{USER} && $console->{USER}->{Name} ? sprintf(' from user: %s', $console->{USER}->{Name}) : "" )
        );
    $console->redirect({url => '?cmd=movetimerlist', wait => 1})
        if($console->typ eq 'HTML');
}

# ------------------
# Name:  movetimerlist
# Descr: List Rules to move timer in a table display.
# Usage: $self->movetimerlist($watcher, $console);
# ------------------
sub movetimerlist {
    my $self = shift || return error('No object defined!');
    my $watcher = shift || return error('No watcher defined!');
    my $console = shift || return error('No console defined!');

    my %f = (
        'id' => gettext('Service'),
        'source' => gettext('Source'),
        'destination' => gettext('Destination'),
        'move' => gettext('Move timer'),
        'original' => gettext('Change original timer'),
    );

    my $sql = qq|
    select
      id as \'$f{'id'}\',
      source as \'$f{'source'}\',
      destination as \'$f{'destination'}\',
      move as \'$f{'move'}\',
      original as \'$f{'original'}\'
    from
      MOVETIMER
    order by 
      id
    |;

    my $fields = fields($self->{dbh}, $sql);
    my $erg = $self->{dbh}->selectall_arrayref($sql);

    my %m;
    my %d;
    my $mr = $self->_move_rules();
    foreach my $mrr (@{$mr}) {
      $m{$mrr->[0]} = $mrr->[1]; 
    }

    my $dr = $self->_original_timer_rules();
    foreach my $drr (@{$dr}) {
      $d{$drr->[0]} = $drr->[1];
    }

    my $modC = main::getModule('CHANNELS');
    map { 
      $_->[1] = $modC->ChannelToName($_->[1]);
      $_->[2] = $modC->ChannelToName($_->[2]);
      $_->[3] = $m{$_->[3]};
      $_->[4] = $d{$_->[4]};
    } @$erg;

    unshift(@$erg, $fields);

    $console->table($erg);
}

# ------------------
sub _move_rules {
# ------------------
    my $self = shift || return error('No object defined!');

    return [
            [ 'y', gettext('Allways') ],
            [ 'n', gettext('Newer') ],
            [ 'collision', gettext('If collision detected') ],
          ];
}

# ------------------
sub _original_timer_rules {
# ------------------
    my $self = shift || return error('No object defined!');

    return [
            [ 'move', gettext('Move timer') ],
            [ 'keep', gettext('Keep inactiv original timer') ],
            [ 'copy', gettext('Copy original timer') ],
          ];
}

1;
