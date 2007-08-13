package XXV::MODULES::CHRONICLE;

use strict;
use Tools;
use Locale::gettext;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $self = shift || return error ('No Object!' );

    my $args = {
        Name => 'CHRONICLE',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module store recordings at chronicle.'),
        Version => '0.91',
        Date => '09.01.2007',
        Author => 'a.brachold',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
        },
        Commands => {
            chrlist => {
                description => gettext('List recording chronicle'),
                short       => 'chrl',
                callback    => sub{ $self->list(@_) },
                DenyClass   => 'rlist',
            },
            chrsearch => {
                description => gettext("Search at chronicle for 'text'"),
                short       => 'chrs',
                callback    => sub{ $self->search(@_) },
                DenyClass   => 'rlist',
            },
            chrdelete => {
                description => gettext("Delete at chronicle with 'id'"),
                short       => 'chrd',
                callback    => sub{ $self->delete(@_) },
                DenyClass   => 'redit',
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

    # The Initprocess
    my $erg = $self->_init or return error('Problem to initialize module');

    return $self;
}

# ------------------
sub _init {
# ------------------
    my $self = shift || return error ('No Object!' );

    if($self->{active} eq 'y') {
      return 0, panic("Session to database is'nt connected")
        unless($self->{dbh});

      # don't remove old table, if updated rows => warn only
      tableUpdated($self->{dbh},'CHRONICLE',6,0);

      # Look for table or create this table
      my $version = main::getVersion;
      $self->{dbh}->do(qq|
        CREATE TABLE IF NOT EXISTS CHRONICLE (
            id int unsigned auto_increment not NULL,
            hash varchar(16) NOT NULL default '',
            title text NOT NULL default '',
            channel_id varchar(100) NOT NULL default '',
            starttime datetime NOT NULL default '0000-00-00 00:00:00',
            duration int NOT NULL default '0',
            PRIMARY KEY  (id),
            UNIQUE KEY (hash) 
          ) COMMENT = '$version'
      |);

      main::after(sub{
          my $m = main::getModule('RECORDS');
          $m->updated(sub{
            return 0 if($self->{active} ne 'y');

            lg 'Start chronicle callback to store recordings!';
            return $self->_insertData();

          });
          return 1;
      }, "CHRONICLE: Install callback at update recordings ...", 15);
    }
    1;
}

# ------------------
sub _insertData {
# ------------------
    my $self = shift || return error ('No Object!' );

    my $sql = qq|
INSERT IGNORE INTO CHRONICLE 
  SELECT 
    0, PASSWORD(CONCAT(e.channel_id,e.starttime,title)),
    REPLACE(IF(Length(e.subtitle)<=0, IF(left(e.title,1) = '%',right(e.title,length(e.title)-1),e.title), CONCAT_WS('~',e.title,e.subtitle)),'~%','~') as title,
    IF(e.channel_id <> "<undef>",e.channel_id , NULL),
    e.starttime,
    e.duration
  FROM OLDEPG as e,RECORDS as r
  WHERE r.eventid = e.eventid
|;
    $self->{dbh}->do($sql);

    return 1;
}

# ------------------
sub list {
# ------------------
    my $self = shift;
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my %f = (
        'id' => umlaute(gettext('Service')),
        'title' => umlaute(gettext('Title')),
        'subtitle' => umlaute(gettext('Subtitle')),
        'channel' => umlaute(gettext('Channel')),
        'day' => umlaute(gettext('Day')),
        'start' => umlaute(gettext('Start')),
        'stop' => umlaute(gettext('Stop'))
    );

    my $sql = qq|
SELECT
  CHRONICLE.id as $f{'id'},
  CHRONICLE.title as $f{'title'},
  CHRONICLE.channel_id as $f{'channel'},
  DATE_FORMAT(CHRONICLE.starttime, '%d.%m.%Y') as $f{'day'},
  DATE_FORMAT(CHRONICLE.starttime, '%H:%i') as $f{'start'},
  DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(CHRONICLE.starttime) + CHRONICLE.duration), '%H:%i') as $f{'stop'}
FROM CHRONICLE
ORDER BY CHRONICLE.starttime
|;
    my $fields = fields($self->{dbh}, $sql);
    my $erg = $self->{dbh}->selectall_arrayref($sql);
    unshift(@$erg, $fields);
    $console->table($erg);

    return 1;
}

# ------------------
sub search {
# ------------------
    my $self = shift;
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $quest  = shift || return $console->err(gettext("No 'text' to search! Please use chrsearch 'text'"));

    $quest =~ s/\'/\./sg;
    $quest =~ s/\+/\\\\\+/sg;

    my %f = (
        'id' => umlaute(gettext('Service')),
        'title' => umlaute(gettext('Title')),
        'subtitle' => umlaute(gettext('Subtitle')),
        'channel' => umlaute(gettext('Channel')),
        'day' => umlaute(gettext('Day')),
        'start' => umlaute(gettext('Start')),
        'stop' => umlaute(gettext('Stop'))
    );

    my $sql = qq|
SELECT
  CHRONICLE.id as $f{'id'},
  CHRONICLE.title as $f{'title'},
  CHRONICLE.channel_id as $f{'channel'},
  DATE_FORMAT(CHRONICLE.starttime, '%d.%m.%Y') as $f{'day'},
  DATE_FORMAT(CHRONICLE.starttime, '%H:%i') as $f{'start'},
  DATE_FORMAT(FROM_UNIXTIME(UNIX_TIMESTAMP(CHRONICLE.starttime) + CHRONICLE.duration), '%H:%i') as $f{'stop'}
FROM CHRONICLE
WHERE CHRONICLE.title RLIKE ?
ORDER BY CHRONICLE.starttime
|;
    my $fields = fields($self->{dbh}, $sql);
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($quest)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    my $erg = $sth->fetchall_arrayref();
    unshift(@$erg, $fields);
    $console->table($erg);

    return 1;
}

# ------------------
sub delete {
# ------------------
    my $self = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');
    my $items  = shift || return $console->err(gettext("No ID to delete! Please use chrdelete 'id'"));

    my @ids  = reverse sort{ $a <=> $b } split(/[^0-9]/, $items);

    my $sql = sprintf('DELETE FROM CHRONICLE WHERE id in (%s)', join(',' => ('?') x @ids)); 
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute(@ids)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);

    return 1;
}

1;
