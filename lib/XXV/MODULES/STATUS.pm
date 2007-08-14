package XXV::MODULES::STATUS;
use strict;

use Tools;
use Socket;
use Sys::Hostname;
use Locale::gettext;
use File::Basename;
use File::Find;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'STATUS',
        Prereq => {
            # 'Perl::Module' => 'Description',
        },
        Description => gettext('This module analyze your system and print the result.'),
        Version => '0.95',
        Date => '2007-08-14',
        Author => 'xpix',
        Level => 'user',
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
            },
            whoBinary => {
                description => sprintf(gettext("Path of command '%s'"),'who'),
                default     => "/usr/bin/who",
                type        => "file",
                required    => gettext('This is required!'),
            },
            wcBinary => {
                description => sprintf(gettext("Path of command '%s'"),'wc'),
                default     => "/usr/bin/wc",
                required    => gettext('This is required!'),
                type        => "file",
            },
            dfBinary => {
                description => sprintf(gettext("Path of command '%s'"),'df'),
                default     => "/bin/df",
                required    => gettext('This is required!'),
                type        => "file",
            },
            interval => {
                description => gettext('Interval in seconds to remember data'),
                default     => 60,
                type        => "integer",
            },
            history => {
                description => gettext('How long to remember the historical data in hours'),
                default     => 3,
                type        => "integer",
            },
            font => {
                description => gettext('True type font to draw image text.'),
                default     => 'Vera.ttf',
                type        => 'list',
                choices     => $obj->findttf,
            },
            graphic => {
                description => gettext('Show collected data as diagram?'),
                default     => 'y',
                type        => 'confirm',
            },
        },
        Commands => {
            all => {
                description => gettext('Display all relevant informations about this system'),
                short       => 'sa',
                callback    => sub{
                    my ($watcher, $console) = @_;
                    $console->setCall('vitals');
                    $obj->vitals(@_);

                    $console->setCall('filesys');
                    $obj->filesys(@_);

                    $console->setCall('memory');
                    $obj->memory(@_);

                    $console->setCall('network');
                    $obj->network(@_);

                    $console->setCall('hardware');
                    $obj->hardware(@_);
                },
            },
            vitals => {
                description => gettext('Display the vitals informations'),
                short       => 'sv',
                callback    => sub{ $obj->vitals(@_) },
            },
            network => {
                description => gettext('Display the network informations'),
                short       => 'sn',
                callback    => sub{ $obj->network(@_) },
            },
            hardware => {
                description => gettext('Display the hardware informations'),
                short       => 'sh',
                callback    => sub{ $obj->hardware(@_) },
            },
            memory => {
                description => gettext('Display the memory informations'),
                short       => 'sm',
                callback    => sub{ $obj->memory(@_) },
            },
            filesys => {
                description => gettext('Display the file system informations'),
                short       => 'sf',
                callback    => sub{ $obj->filesys(@_) },
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

    # Interval to read timers and put to DB
    Event->timer(
        interval => $self->{interval},
        prio => 6,  # -1 very hard ... 6 very low
        cb => sub{
            $self->remember();
        },
    ) if($self->{active} eq 'y');

    $self->{LastWarning} = 0;

	return $self;
}

# ------------------
sub remember {
# ------------------
    my $obj = shift  || return error ('No Object!' );

    my $longsteps = int(($obj->{history} * 60 * 60) / $obj->{interval});

    $obj->watchDog($obj->mounts());

    my $data = {
        timestamp  => time,
        load        => $obj->load('clear'),
        util        => $obj->util('clear'),
        users       => $obj->users('clear'),
        usage       => $obj->mounts('clear'),
        memory      => $obj->meminfo('clear'),
        network     => $obj->netDevs('clear'),

    };
    push(@{$obj->{rememberstack}}, $data);

    if(scalar @{$obj->{rememberstack}} >= $longsteps) {
        shift @{$obj->{rememberstack}};
    }
}


# ------------------
sub vitals {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $output = {
        name    => $obj->name(),
        IP      => $obj->IP(),
        kernel  => $obj->kernel(),
        uptime  => $obj->uptime(),
        users   => $obj->users(),
        load    => $obj->load(),
        util    => $obj->util(),
    };

    my $param = {
        headingText => gettext('Vitals'),
        stack => $obj->{rememberstack},
        history => $obj->{history} * 60 * 60,
        interval => $obj->{interval},
        font => sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font}),
    };
    return $console->table($output,$param);
}

# ------------------
sub network {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $interfaces = $obj->netDevs();
    my $param = {
        headingText => gettext('Network'),
        stack => $obj->{rememberstack},
        history => $obj->{history} * 60 * 60,
        interval => $obj->{interval},
        font => sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font}),
    };
    return $console->table($interfaces,$param);
}

# ------------------
sub hardware {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my ($number, $model, $speed, $cache, $bogomips) = $obj->CPU();
    my $pci = $obj->pci();
    my $ide = $obj->ide();
    my $scsi = $obj->scsi();

    my $output = {
        Processors  => $number,
        Model       => $model,
        ChipSpeed   => $speed,
        CacheSize   => $cache,
        SystemBogomips  => $bogomips,
    };
    $console->table($output, {headingText => gettext('CPU'), hide_HeadRow => 1});
    $console->table($pci, {headingText => gettext('PCI'), drawRowLine => 1, hide_HeadRow => 1})
      if($pci);
    $console->table($ide, {headingText => gettext('IDE')})
      if($ide && scalar @{$ide} > 1);
    $console->table($scsi, {headingText => gettext('SCSI')})
      if($scsi && scalar @{$scsi} > 1);
}

# ------------------
sub memory {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $ret = $obj->meminfo();
    my $param = {
        headingText => gettext('Memory'),
        stack => $obj->{rememberstack},
        history => $obj->{history} * 60 * 60,
        interval => $obj->{interval},
        font => sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font}),
    };
    return $console->table($ret,$param);
}

# ------------------
sub filesys {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $watcher = shift || return error ('No Watcher!');
    my $console = shift || return error ('No Console');

    my $ret = $obj->mounts();
    my $param = {
        headingText => gettext('Filesystems'),
        usage => $ret,
        font => sprintf("%s/%s",$obj->{paths}->{FONTPATH},$obj->{font}),
        graphic => ($obj->{graphic} eq 'y' ? 1 : 0),
    };
    return $console->table($ret,$param);
}


#############################################################################
#                           Helper Functions
#############################################################################


# Takes Celcius temperatures and converts to Farenheit

sub tempConvert {
    my $obj = shift || return error ('No Object!' );
    my $celcius = $_[0];

    my $result = (( $celcius * 9) / 5 ) + 32;

    $result = sprintf("%.1f", $result);

    $result .= "&#176 F";

    return $result;

}

# Get the system's name

sub name {
    my $obj = shift || return error ('No Object!' );

    my $result = hostname();
    return $result;

}

# Get the system's IP address

sub IP {
    my $obj = shift || return error ('No Object!' );

    my $result = inet_ntoa(scalar(gethostbyname($obj->name())) || scalar(gethostbyname('localhost')));
    return $result;

}

# Get the system's kernel version

sub kernel {
    my $obj = shift || return error ('No Object!' );

    my $result = load_file("/proc/sys/kernel/osrelease");
    $result =~ s/\n//sig;
    return $result;

}

# Get the system's uptime

sub uptime {
    my $obj = shift || return error ('No Object!' );

    my $buffer = load_file('/proc/uptime');

    my @list = split / /, $buffer;
    my $ticks = sprintf("%.0u", $list[0]);
    my $mins  = $ticks / 60;
    $mins  = sprintf("%.0u", $mins);
    my $hours = $mins / 60;
    $hours = sprintf("%.0u", $hours);
    my $days  = ($hours / 24);
    $days  = sprintf("%.0u", $days);
    $hours = $hours - ($days * 24);
    $hours = sprintf("%.0u", $hours);
    $mins  = $mins - ($days * 60 * 24) - ($hours * 60);

    my $result = '';
    if ( $days == 1 ) {
        $result .= "${days} ".gettext("day");
    }
    elsif ( $days == 0 ) {
        $result .= '';
    }
    else {
        $result .= "${days} ".gettext("days");
    }

    if ( $days > 0 && ( $hours > 0 || $mins > 0 )) {
        $result .= ", ";
    }

    if ( $hours == 1 ) {
        $result .= "${hours} ".gettext("hour");
    }
    elsif ( $hours == 0) {
        $result .= '';
    }
    else {
        $result .= "${hours} ".gettext("hours");
    }

    if ( $hours > 0 && $mins > 0 ) {
        $result .= ", ";
    }

    if ( $mins == 1 ) {
        $result .= "${mins} ".gettext("minute");
    }
    elsif ($mins == 0 ) {
        $result .= '';
    }
    else {
        $result .= "${mins} ".gettext("minutes");
    }

    return $result;

}

# Get information on network devices in the system
sub netDevs {
    my $obj = shift || return error ('No Object!' );
    my $clr = shift || 0;
    my $buffer = load_file('/proc/net/dev');

    my $interfaces = [[qw/Interface RxBytes RxPackets RxErrs RxDrop TxBytes TxPackets TxErrs TxDrop/]];
       $interfaces = [] if($clr);

    foreach my $line (split(/\n/, $buffer)) {
        my @data = split(/[:|\s]+/, $line);
        next unless($data[2] =~ /^\d+$/);
        unless($clr) {
            $data[2] = convert($data[2]);
            $data[10] = convert($data[10]);
        }
        push(@$interfaces, [@data[1..5], @data[10..13]]);
    }

    return $interfaces;
}

# Get the current memory info
sub meminfo {
    my $obj = shift || return error ('No Object!' );
    my $clr = shift || 0;

    my $ret = {};
    my $buffer = load_file "/proc/meminfo";
    foreach my $zeile (split('\n', $buffer)) {
        next unless($zeile =~ /kB/);
        my ($name, $value) = split(':\s+', $zeile);
        $value =~ s/ kB//sig;

        $value = convert($value * 1024)
            unless($clr);

        $ret->{$name} = $value;
    }
    return $ret;
}

# Get current cpu info

sub CPU {
    my $obj = shift || return error ('No Object!' );

    my $buffer = load_file('/proc/cpuinfo');

    my @rows = split /\n/, $buffer;
    my $number = scalar grep /processor\s+:/, @rows;
    my @modelList = grep /model name\s+:/, @rows;
    my @speedList = grep /cpu MHz\s+:/, @rows;
    my @cacheList = grep /cache size\s+:/, @rows;
    my @bogomipsList = grep /bogomips\s+:/, @rows;

    my ($crap, $model) = split /:/, $modelList[0], 2;
    $model =~ s/\s+//;

    ($crap, my $speed) = split /:/, $speedList[0], 2;
    $speed = sprintf("%.0u", $speed);
    $speed .= " MHz";

    ($crap, my $bogomips) = split /:/, $bogomipsList[0], 2;
    $bogomips = sprintf("%.0u", $bogomips);

    my $cache = '';

    ($crap, $cache) = split /:/, $cacheList[0], 2;
    if ($cache eq '') {
        $cache = gettext("No on-chip cache.");
    }

    return ($number, $model, $speed, $cache, $bogomips);

}

# Get CPU usage info and return a percentage

sub util {
    my $obj = shift || return error ('No Object!' );

    open(STAT, "/proc/stat") or return error "Can't open /proc/stat\n";
    my $buffer = <STAT>;
    close(STAT);

    my ($name, $user, $nice, $system, $idle) = split /\s+/, $buffer;
    my $usage = $user + $nice + $system;
    my $total = $user + $nice + $system + $idle;

    #Wait 1 second for cpu time to accumulate for comparison
    #More than 1 second delays the script too much, and sleep won't
    #take an argument < 1
    sleep(1);

    open (STAT, "/proc/stat") or return error "Can't open /proc/stat\n";
    $buffer = <STAT>;
    close(STAT);

    my ($newName, $newUser, $newNice, $newSystem, $newIdle) = split /\s+/, $buffer;
    my $newUsage = $newUser + $newNice + $newSystem;
    my $newTotal = $newUser + $newNice + $newSystem + $newIdle;

    my $deltaUsage = $newUsage - $usage;
    my $deltaTotal = $newTotal - $total;

    my $percent = 0;

    $percent = ($deltaUsage / $deltaTotal) * 100
      if($deltaTotal != 0);

    $percent = sprintf("%.1f", $percent);

    return($percent);

}

# Get the number of current users logged in

sub users {
    my $obj = shift || return error ('No Object!' );

    my $result = `$obj->{whoBinary} | $obj->{wcBinary} -l`
        or return error "Can't execute $obj->{whoBinary} or $obj->{wcBinary}\n";
    $result =~ s/\n//g;
    return $result;

}

# Get the list of PCI devices

sub pci {
    my $obj = shift || return error ('No Object!' );

    return 0
      if(! -r "/proc/pci");

    my $buffer = load_file("/proc/pci");
    my $ret;
    foreach my $zeile (split(/\n/, $buffer)) {
        if($zeile =~ /(bridge|controller|interface)\:\s+(.+)/i) {
            $ret->{ucfirst($1)} .= "$2\n";
        }
    }
    return $ret;
}

# Get the list of IDE devices

sub ide {
    my $obj = shift || return error ('No Object!' );

    my @ideModelList;
    my @ideCapacityList;
    my $count = 0;

    my @dirList = glob ("/proc/ide/*");
    my $ret = [[qw/Device Model Capacity Cache/]];
    foreach my $device (@dirList) {
        next unless($device =~ /ide\/hd/);

        my $model = load_file("${device}/model");
        $model =~ s/\n//g;

        my $cap = 0;
           $cap = load_file("${device}/capacity")
            if(-e "${device}/capacity");
        my $cache = 0;
           $cache = load_file("${device}/cache")
            if(-e "${device}/cache");
        push(@$ret,
            [
                $device,
                $model,
                convert($cap * 512),
                convert($cache * 1024),
            ]
        );
    }

    return $ret;
}

# Get the list of SCSI devices

sub scsi {
    my $obj = shift || return error ('No Object!' );

    my $ret = [[qw/Device Vendor Model Type/]];
    my $file = "/proc/scsi/scsi";

    if ( -r $file){
        my ( $host, $channel, $id, $lun, $vendor, $model, $type )   ;
        my $dev_no = 'a';
        my $cd_no = '0';
        my $st_no = '0';
        open(F,$file) 
            or return error "Can't open $file : $!\n";;
        while(<F>) {
            if(/Host: (\S+) Channel: (\d+) Id: (\d+) Lun: (\d+)/) {
                $host = $1, $channel = $2, $id = $3, $lun = $4;
            }
            if(/Vendor: (.+)\s+Model: (.+)\s+Rev:/) {
                $vendor = $1, $model = $2;
                $vendor =~ s/^\s+//g; 
                $vendor =~ s/\s+$//g; 
                $model =~ s/^\s+//g;
                $model =~ s/\s+$//g;

                $_ = <F>; 
                if(/Type:(.+)\s+ANSI/) {
                    $type = $1;
                    $type =~ s/^\s+//g;
                    $type =~ s/\s+$//g; 
                }

                my $device;
                if($type eq 'Direct-Access') { # Disk
                    $device = "/dev/sd$dev_no";
                    $dev_no++;
                } elsif($type eq 'CD-ROM') {
                    $device = "/dev/scd$cd_no";
                    $cd_no++;
                } elsif($type eq 'Sequential-Access') { # Streamer
                    $device = "/dev/st$st_no";
                    $st_no++;
                } 

                push(@$ret,
                    [
                        "$device (ch: $channel, lun: $lun, scsi: $id)",
                        $vendor,
                        $model,
                        $type,
                    ]
                ) if($device);
             }
        }
        close(F);
    }
    return $ret;
}

# Get the current load averages

sub load {
    my $obj = shift || return error ('No Object!' );
    my $clr = shift || 0;

    my $buffer = load_file("/proc/loadavg");
    my @list = split(' ', $buffer);
    my $c = 5;
    my $ret;

    return \@list if($clr);

    foreach my $entry (@list[0..2]) {
        $ret .= sprintf("%s last %d min\n", $entry, $c);
        $c += 5;
    }

    return $ret;

}

# Get the status of currently mounted filesystems
sub mounts{
    my $obj = shift || return error ('No Object!' );
    my $clr = shift || 0;

    my $df = `$obj->{dfBinary} -TP -x cdfs -x iso9660 -x udf`
        or return error "Can't execute $obj->{dfBinary} $!\n";
    my $ret = [[qw/FS Typ Space Used Free Cap. Mount/]];

    foreach my $zeile (split('\n', $df)) {
        my @data = split('\s+', $zeile);
        next if($data[2] !~ /^\d+$/);

        $data[0] =~ s/[\-\s]/_/sg;

        if($clr) {
            push(@$ret, $data[5]);
        } else {
            map {$_ = convert($_ * 1024)} @data[2..4];
            push(@$ret, \@data);
        }
    }
    return $ret;
}

# ------------------
sub videoMounts {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $videodir = shift || return error ('No Video dir!');
    my $mounts = $obj->mounts;

    my $ret = [];

    for (@$mounts) {
        push(@$ret, $_)
            if($_->[0] =~ /^$videodir/i);
    }

    $ret = $mounts unless(scalar @$ret);

    return $ret;
}

# ------------------
sub findttf
# ------------------
{
    my $obj = shift || return error ('No Object!' );
    my $found;
    find({ wanted => sub{
                if($File::Find::name =~ /\.ttf$/sig) {
                    my $l = basename($File::Find::name);
                    push(@{$found},[$l,$l]);
                }
           },
           follow => 1,
           follow_skip => 2,
        },
        $obj->{paths}->{FONTPATH}
    );
    error "Can't find useful font at : $obj->{paths}->{FONTPATH}"
        if(scalar $found == 0);
    return $found;
}

# ------------------
sub watchDog {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $mou = shift  || return error ('No Data!' );

    # Not all 15 seconds a panic message ;)
    return if($obj->{LastWarning}+900 > time);

    foreach my $m (@$mou) {
        next unless($m->[0] =~ /^\//);
        if(int($m->[5]) >= 98 ) {
            my $rm = main::getModule('REPORT');
            $rm->news(
                sprintf(gettext("PANIC! Only %s%% space left on device %s"),(100 - int($m->[5])),$m->[0]),
                sprintf(gettext("Device has space %s from %s used!"), $m->[3], $m->[2]),
                'sa',
                undef,
                'important'
            );
            $obj->{LastWarning} = time;
        }
    }
}


1;
