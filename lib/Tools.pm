package Tools;

@ISA = qw(Exporter);

use FindBin qw($RealBin);
use lib sprintf("%s", $RealBin);
use lib sprintf("%s/../lib", $RealBin);

use Data::Dumper;
$Data::Dumper::Indent = 1;
#$Data::Dumper::Maxdepth = 2;

use IO::File;
use Socket;
use Time::HiRes qw( gettimeofday );

our $DUMPSTACK  = 0;
our $VERBOSE    = 3;
our $LOG        = sub{ warn @_ };
our $BENCH      = {};
our $LOGCALLB   = sub{ };
our $DBH        = {};

@EXPORT = qw(&datum &stackTrace &lg &event &debug &error &panic &rep2str &dumper &getFromSocket &fields
 &load_file &save_file &tableExists &tableUpdated &buildsearch &deleteDir &getip &convert &int &entities &reentities &bench
 &fmttime &getDataByTable &getDataById &getDataBySearch &getDataByFields &umlaute &touch);


# ------------------
sub fmttime {
# ------------------
    my $tim = shift  || 0;
    return $tim if(index($tim, ':') > -1);

    my $value = sprintf('%04d',$tim);
    my $ret = sprintf('%02d:%02d', substr($value, 0, 2), substr($value, 2, 2));
    return $ret;
}

# ------------------
sub datum {
# ------------------
    my $zeit = shift  || time;
    my $typ  = shift  || 'voll';
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
            localtime($zeit);

    if(lc($typ) eq 'voll') {
        return sprintf('%02d:%02d:%02d %02d.%02d.%04d',
            $hour, $min, $sec, $mday, $mon+1, $year+1900);
    } elsif(lc($typ) eq 'tag') {
        return sprintf('%02d.%02d.%04d',
            $mday, $mon+1, $year+1900);
    } elsif (lc($typ) eq 'int') {
        # 1901-01-01T00:00+00:00
        return sprintf('%04d-%02d-%02dT%02d:%02d+01:00',
            $year+1900, $mon+1, $mday, $hour, $min );
    } elsif (lc($typ) eq 'rss') {
        # 23 Aug 1999 07:00:00 GMT
        my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
        return sprintf('%02d %s %04d %02d:%02d:%02d GMT',
            $mday, $abbr[$mon], $year+1900, $hour, $min, $sec );
    } else {
        return sprintf('%02d:%02d:%02d',
            $hour, $min, $sec);
    }
}

#returns a string containg the stacktrace
# ------------------
sub stackTrace {
# ------------------
    my $result;
    my $s;
    my $n = 0;
    my @res;
    do {
        my ($package, $filename, $line, $subroutine) = caller($n++);
        if($filename) {
            $s = sprintf("%s:%s (%s)", $filename||"", $line||"", $subroutine||"");
            push(@res, $s);
        } else {
            $s = 0;
        }
    } while ($s);

    my $evalon = 0;
    $evalon = 1
        if(scalar @res > 4
            and $res[4] =~ /\(eval\)/si
            and $res[4] !~ /XXV/si);

    $result .= "\n=========== top of stack =========\n";
    $result .= join("\n   ", @res);
    $result .= "\n=========== end of stack =========\n\n";
    return ($result, $evalon);
}

# ------------------
sub lg {
# ------------------
    my $msg = shift;
    my $lev = shift || 5;
    my $deep = shift || 1;

    return 1 if($VERBOSE < $lev);

    $msg = 'ERR:202 ' . $msg
        unless($msg =~ /^ERR:\d{3}/);

    if($VERBOSE > 5 or $DUMPSTACK) {
        my ($stack, $evalon) = &stackTrace;
        $msg .= $stack if($evalon != 1);
    }

    my ($package, $filename, $line, $subroutine) = caller($deep);

    my  $module = '';
        $module = (split('::', $package))[-1]
            if($package);

    &{$LOG}($module . ': ' . $msg);

    return 1;
}

# ------------------
sub event {
# ------------------
    my $msg = sprintf(shift, @_);

    my ($package, $filename, $line, $subroutine) = caller(3);

    &lg('EVT:270 ' . $msg, 3, 2);

    &{$LOGCALLB}($module, $subroutine, $msg);

    return 1;
}

# ------------------
sub debug {
# ------------------
    my $msg = sprintf(shift, @_);

    &lg('ERR:250 ' . $msg, 2, 2);

    return 1;
}

# ------------------
sub error {
# ------------------
    my $msg = sprintf(shift, @_);

    &lg('ERR:501 ' . $msg, 1, 2);

    return undef;
}

# ------------------
sub panic {
# ------------------
    my $msg = sprintf(shift, @_);

    &lg('ERR:550 ' . $msg, 1, 2);

    return undef;
}

# ------------------
sub getFromSocket {
# ------------------
    my $sock = shift or return undef;

    my (@Data, $Line);
    my $len = 0;

  	do {
	  	$Line = <$sock> || 0;
          $len += length($Line);
	  	$Line =~ s/\r\n//g;
	  	push(@Data, $Line);
	  } while($Line);

    return (\@Data, $len);
}


# ------------------
sub rep2str {
# ------------------
    my %args = @_;
    my $text = $args{-text};
    $text =~ s/\<(.+?)\>/$args{"-$1"}/sig;
    return $text;
}

# ------------------
sub dumper {
# ------------------
    my $var = shift || '<undef>';
    my $args = @_;

    $Data::Dumper::Maxdepth = $args->{d}
        if($args->{d});
    $Data::Dumper::Indent = $args->{i}
        if($args->{d});

    debug Dumper( $var );
}

# ------------------
sub fields {
# ------------------
    my $dbh = shift || return error ('No DBH!' );
    my $str = shift || return error ('No SQL!');

    $str =~ s/order\s+by.+//sig;
    my $sql = sprintf('%s %s 0 = 1', $str, ($str =~ /where/i ? 'AND' : 'WHERE'));
		my $sth = $dbh->prepare($sql) or return error("$DBI::errstr - $sql");
		$sth->execute or return error("$DBI::errstr - $sql");
		my $fields = $sth->{'NAME'};
    return $fields;
}

# ------------------
sub tableExists {
# ------------------
    my $dbh = shift || return error ('No DBH!' );
    my $name = shift || return error ('No Table!');

    my $erg = $dbh->selectall_arrayref('show tables');
    for(@$erg) {
        return 1 if($name eq $_->[0]);
    }
    return 0;
}

# ------------------
sub tableUpdated {
# ------------------
    my $dbh = shift || return error ('No DBH!');
    my $table = shift || return error ('No Table!');
    my $rows = shift || return error ('No Rows!');
    my $drop = shift || 0;

    # remove old Version, if updated
    if(tableExists($dbh, $table)) {
        my $fields = fields($dbh, 'select * from '.$table);
        if(!$fields || scalar @$fields != $rows) {
            if($drop) {
              lg sprintf('Remove old version from database table %s',$table);
              $dbh->do(sprintf('drop table %s',$table))
                  or return panic sprintf("Can't drop table %s - %s",$table, $DBI::errstr);
            } else {
              panic sprintf(
q|------- !PROBLEM! ----------
Upps, you have a incompatible or corrupted database.
Table %s has %d. It's expected %d rows.
Please check database e.g. with mysqlcheck --all-databases --fast --silent
or use the script contrib/upgrade-xxv.sh to upgrade the database!
----------------------------|#'
                    ,$table
                    ,$fields ? scalar @$fields : 0
                    ,$rows);
              return 0;
            }
        }
    }
    return 1;
}

#--------------------------------------------------------
sub load_file {
#--------------------------------------------------------
	my $file = shift || die "Kein File bei Loader $!";

    lg sprintf('Load file "%s"',
            $file,
        );

	my $fh = IO::File->new("< $file")
	    or return error(sprintf("Can't open %s : %s!",$file,$!));
	my $data;
	while ( defined (my $l = <$fh>) ) {
	        $data .= $l;
	}
	$fh->close;
	return $data;
}

#--------------------------------------------------------
sub save_file {
#--------------------------------------------------------
    my ($file, $data) = @_;
	return unless($file);

    $data =~ s/\r\n/\n/sig;

    lg sprintf('Save file %s(%s)',
            $file,
            convert(length($data))
        );

	my $fhi = new IO::File("> $file")
	    or return error(sprintf("Can't write %s : %s!",$file,$!));
	print $fhi $data;
	$fhi->close;

    return $file
}


#--------------------------------------------------------
sub _buildsearchcomma {
#--------------------------------------------------------
    my ($queryField, $Search) = @_;

    my $out;
    foreach my $su (split(/\s*,\s*/, $Search)) {
#   $su =~ s/\./\\\\\./sg;
    $su =~ s/\'/\\\\\'/sg;
    $su =~ s/\"/\./sg;
    $su =~ s/\+/\\\\\+/sg;
    $su =~ s/\?/\\\\\?/sg;
    $su =~ s/\(/\\\\\(/sg;
    $su =~ s/\)/\\\\\)/sg;

    $out .= ' AND ' if($out);
    if($su =~ s/^\-+//) {
        $out .= qq| ($queryField NOT RLIKE "$su")|;
    } else {
        $su =~ s/^\&+//; #remove for backward compatibility
        $out .= qq| ($queryField RLIKE "$su")|;
    }
  }
# dumper($out);
	return $out;
}

#--------------------------------------------------------
sub _buildsearchlogical {
#--------------------------------------------------------
  my ($queryField, $Search) = @_;

  my $out;
  my $op = 1;
  $out = " (";
  foreach my $su (split(/( AND NOT | OR | AND )/, $Search)) {
   
      if($su eq " AND ") {
        $out .= " AND" unless($op);
        $op = 1;
      } elsif($su eq " OR ") {
        $out .= " OR" unless($op);
        $op = 1;
      } elsif($su eq " AND NOT ") {
        $out .= " AND NOT" unless($op);
        $op = 1;
      } else {
        $out .= " AND" unless($op);
      
#       $su =~ s/\./\\\\\./sg;
        $su =~ s/\'/\\\\\'/sg;
        $su =~ s/\"/\./sg;
        $su =~ s/\+/\\\\\+/sg;
        $su =~ s/\?/\\\\\?/sg;
        $su =~ s/\(/\\\\\(/sg;
        $su =~ s/\)/\\\\\)/sg;

        $out .= qq| ($queryField RLIKE "$su")|;

        $op = 0;
      }
  }
  $out .= " )";
# dumper($out);
  return $out;
}


#--------------------------------------------------------
sub buildsearch {
#--------------------------------------------------------
    my ($InFields, $Search) = @_;
    my @fields = split(/\s*,\s*/, $InFields);
    my $queryField = scalar(@fields) > 1 ? qq|CONCAT_WS("~",$InFields)| : qq|$InFields|;

    if( grep(/ AND /, $Search) 
        or grep(/ OR /, $Search) 
        or grep(/ NOT /, $Search)) {
    return _buildsearchlogical($queryField, $Search);
  } else {
    return _buildsearchcomma($queryField, $Search);
  }
}
# ------------------
sub deleteDir {
# ------------------
    my $dir = shift || return;

    lg sprintf('Delete directory "%s" in the system',
            $dir,
        );

    foreach my $file (glob(sprintf('%s/*', $dir))) {
        deleteDir($file)
            if(-d $file);
        unlink $file;
    }
    rmdir $dir;
    return 1;
}

# ------------------
sub getip {
# ------------------
    my $handle = shift  || return error ('No Handle!' );
    my $p = getpeername($handle)
        or return;
    my($port, $iaddr) = unpack_sockaddr_in($p);
    my $ip = inet_ntoa($iaddr);

    return $ip;
}

# ------------------
# Name:  getDataByTable
# Descr: universal routine to get data by table
# Usage: my $hash = $obj->getDataByTable('TABLE', ['ID']);
# ------------------
sub getDataByTable {
    my $table = shift || return error ('No Table!' );
    my $key = shift;
    unless($key) {
      my $erg = &fields($DBH, 'select * from '.$table)
          or return error sprintf("Can't execute query: %s.",$DBI::errstr);
      $key = $erg->[0];
    } 

    my $sth = $DBH->prepare(sprintf('select * from %s',$table));
    $sth->execute()
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    return $sth->fetchall_hashref($key);
}


# ------------------
# Name:  getDataById
# Descr: universal routine to get data by id from table
# Usage: my $hashrow = $obj->getDataById(123, 'TABLE', ['ID']);
# ------------------
sub getDataById {
    my $id = shift  || return error ('No Object!' );
    my $table = shift || return error ('No Table!' );
    my $key = shift  || &fields($DBH, 'select * from '.$table)->[0];

    my $sth = $DBH->prepare(sprintf('select * from %s where %s = ?',$table, $key));
    $sth->execute($id)
        or return error sprintf("Can't execute query: %s.",$sth->errstr);
    return $sth->fetchrow_hashref();
}

# ------------------
# Name:  getDataBySearch
# Descr: universal routine to get data by search from table
# Usage: my $arref = $obj->getDataBySearch('TABLE', 'ID = 123');
# ------------------
sub getDataBySearch {
    my $table = shift || return error ('No Table!' );
    my $search = shift || return error ('No Searchtxt!' );

    my $sql = sprintf('select * from %s where %s',
                $table, $search);

    my $erg = $DBH->selectall_arrayref($sql);
    return $erg;
}

# ------------------
# Name:  getDataByFields
# Descr: universal routine to get data by fields from table
# Usage: my $arref = $obj->getDataBySearch('TABLE', 'ID', ['WHERE']);
# ------------------
sub getDataByFields {
    my $table = shift || return error ('No Table!' );
    my $field = shift || '*';
    my $where = shift || '';

    my $sql = sprintf('select %s from %s %s',
                $field, $table, ($where ? 'where '.$where : '')
                );
    my $erg = $DBH->selectcol_arrayref($sql);
    return $erg;
}


# Takes kilobytes and formats for MB and GB if necessary
sub convert {
    my $kbytes = $_[0] / 1024;
    my $result = 0;

    if ( $kbytes > 1048576 ) {
        $result = sprintf("%.2f", $kbytes / 1048576);
        $result .= " GB";
    } elsif ( $kbytes > 1024 ) {
        $result = sprintf("%.2f", $kbytes / 1024);
        $result .= " MB";
    } else {
        $result = sprintf("%.2f", $kbytes);
        $result .= " KB";
    }

    return $result;
}

# ------------------
sub int {
# ------------------
    my $var = shift  || return 0;
    $var =~ s/[^0-9\.\,\-\+]//sig;
    return CORE::int($var);
}

# ------------------
sub entities {
# ------------------
    my $s = shift || return '';

    $s =~ s/&/&amp;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/\"/&quot;/g;
    $s =~ s/([^a-zA-Z0-9&%;:,\.\!\?\(\)\_\|\'\r\n ])/sprintf("&#x%02x;",ord($1))/eg;
    $s =~ s/\r\n/<br \/>/g;

    return $s;
}

# ------------------
sub reentities {
# ------------------
    my $s = shift || return '';

    $s =~ s/\&\#x([a-fA-F0-9][a-fA-F0-9])\;/pack("C", hex($1))/eg;
    $s =~ s/&amp;/&/g;
    $s =~ s/&gt;/>/g;
    $s =~ s/&lt;/</g;
    $s =~ s/&quot;/\"/g;
    $s =~ s/<br \/>/\r\n/g;
    return $s;
}



# ------------------
sub bench {
# ------------------
    my $tag = shift || return $BENCH;

    return $BENCH = {}
        if($tag eq 'CLEAR');

    if(! $BENCH->{$tag} or $BENCH->{$tag} < 1000) {
        $BENCH->{$tag} = scalar gettimeofday;
    } else {
        $BENCH->{$tag} = scalar gettimeofday - $BENCH->{$tag};
    }
}

# ------------------
sub umlaute {
# ------------------
    my $s = shift || return "";

    my %uml = (
        '�' => 'Ae',
        '�' => 'Oe',
        '�' => 'Ue',
        '�' => 'ae',
        '�' => 'oe',
        '�' => 'ue',
        '�' => 'sz'
    );

    my @uml = join("|", keys(%uml));

    $s =~ s/(@uml)/$uml{$1}/eg;

    return $s;
}

# ------------------
sub touch {
# ------------------
    my $file    = shift;
    my $now     = time;
    local (*TMP);

    lg sprintf("Call touch file '%s'", $file );
    utime ($now, $now, $file)
        || open (TMP, ">>$file")
        || error ("Couldn't touch '%s' : %s",$file,$!);
}

1;
