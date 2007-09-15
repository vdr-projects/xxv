package XXV::OUTPUT::NEWS::RSS;
use strict;

use Tools;
use POSIX qw(locale_h);
use Locale::gettext;

# News Modules have only three methods
# init - for intervall or others
# send - send the informations
# read - read the news and parse it

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'NEWS::RSS',
        Prereq => {
            'XML::RSS' => 'SMTP Protocol module to connect and send emails',
        },
        Description => gettext('This NEWS module generates an RSS news feed for your RSS reader.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'y',
                type        => 'confirm',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = shift;
                    my $erg = $obj->init
                        or return error('Problem to initialize news module')
                            if($value eq 'y' and not exists $obj->{INITE});
                    return $value;
                },
            },
            level => {
                description => gettext('Minimum level of messages which can be displayed (1 ... 100)'),
                default     => 1,
                type        => 'integer',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    unless($value >= 1 and $value <= 100) {
                        return undef, 'Sorry, but the value must be between 1 and 100';
                    }
                    return $value;
                },
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

    # host
    $self->{host} = delete $attr{'-host'};

	# who am I
    $self->{MOD} = $self->module;

    # all configvalues to $self without parents (important for ConfigModule)
    map {
        $self->{$_} = $attr{'-config'}->{$self->{MOD}->{Name}}->{$_} || $self->{MOD}->{Preferences}->{$_}->{default}
    } keys %{$self->{MOD}->{Preferences}};

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{TYP} = 'application/xhtml+xml';

    # Initiat after load modules ...
    main::after(sub{
        # The Initprocess
        my $erg = $self->init
            or return error('Problem to initialize news modul!');
    }, "NEWS::RSS: Start initiate rss feed ...")
        if($self->{active} eq 'y');



	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error('No object defined!');
    $obj->{INITE} = 1;

    1;
}

# ------------------
sub createRSS {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $ver  = shift || 1;
    my $account = sprintf("%s@%s", $ENV{USER}, main::getModule('STATUS')->name);
    my $url = sprintf("http://%s:%s/", $obj->{host}, main::getModule('HTTPD')->{Port});

    my $rss;
    if($ver == 1) {
        $rss = XML::RSS->new(
            version => '1.0',
        ) || return error('Problem to create an RSS Object');


        $rss->channel(
            title        => gettext("XXV RSS 1.0"),
            'link'         => $url,
            description  => gettext("Important messages from your VDR/XXV"),
            dc => {
                date       => datum(time,'int'),
                subject    => gettext("XXV messages"),
                creator    => $account,
                language   => setlocale(POSIX::LC_MESSAGES),
            },
            syn => {
                updatePeriod     => "hourly",
                updateFrequency  => "1",
                updateBase       => datum(time, 'int'),
            },
        );

    } elsif($ver == 2) {
        my $lastbuild = (exists $obj->{lastBuildDate} ? $obj->{lastBuildDate} : time);

        $rss = XML::RSS->new(
            version => '2.0',
        ) || return error('Problem to create an RSS Object');

        $rss->channel(
            title          => gettext("XXV RSS 2.0"),
            'link'         => $url,
            description    => gettext("Important messages from your VDR/XXV"),
            language       => setlocale(POSIX::LC_MESSAGES),
            pubDate        => datum(time, 'rss'),
            lastBuildDate  => datum($lastbuild, 'rss'),
            managingEditor => $account,
        );
    }
    $obj->{lastBuildDate} = time;

    return $rss;
}


# ------------------
sub send {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error('No data defined!');

    ++$obj->{COUNT};

    push(@{$obj->{STACK}}, [
        entities($vars->{Title}),
        entities($vars->{Url}),
        entities($vars->{Text}),
        datum($vars->{AddDate},'int'),
        $vars->{LevelName},
    ]);

    lg sprintf('News RSS with nr. %d successfully send at %s', $obj->{COUNT}, scalar localtime);
    1;
}

# ------------------
sub read {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error('No data defined!');

    return undef, lg('This function is deactivated!')
        if($obj->{active} ne 'y');


    $vars->{count} = ++$obj->{NEWSCOUNT};
    $vars->{host}  = $obj->{host};
    $vars->{port}  = main::getModule('HTTPD')->{Port};

    $obj->send($vars);

    return 1;
}

# ------------------
sub req {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $params = shift || {};

    return gettext('The module NEWS::RSS is not active!')
        if($obj->{active} ne 'y');

    my $rss = $obj->createRSS($params->{version})
        || return error('Problem to create a RSS Object!');

    foreach my $entry (@{$obj->{STACK}}) {
        my ($title, $link, $descr, $adddate, $level) = @{$entry};
        $rss->add_item(
            title       => $title,
            link        => $link,
            description => $descr,
    		dc => {
    				date    => $adddate,
     				subject => $level
            },
        );
    }

    return $rss->as_string;
}


1;
