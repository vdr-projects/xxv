package XXV::OUTPUT::NEWS::MAIL;
use strict;

use Tools;
use POSIX qw(locale_h);
use Locale::gettext;

# News Modules have only this methods
# init - for intervall or others
# send - send the informations
# read - read the news and parse it
# req  - read the actual news print this out

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'NEWS::MAIL',
        Prereq => {
            'Mail::SendEasy' => 'Simple platform independent mailer',
        },
        Description => gettext('This NEWS module generate mails for news.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
        Preferences => {
            active => {
                description => gettext('Activate this service'),
                default     => 'n',
                type        => 'confirm',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = shift;
                    my $erg = $obj->init
                        or return undef, gettext("Can't initialize news modul!")
                            if($value eq 'y' and not exists $obj->{INITE});
                    return $value;
                    if($value eq 'y') {
                      my $emodule = main::getModule('EVENTS');
                      if(!$emodule or $emodule->{active} ne 'y') {
                        return undef, sprintf(gettext("Modul can't activated! This modul depends modul %s."),'EVENTS');
                      }
                      my $rmodule = main::getModule('REPORT');
                      if(!$rmodule or $rmodule->{active} ne 'y') {
                        return undef, sprintf(gettext("Modul can't activated! This modul depends modul %s."),'REPORT');
                      }
                    }
                },
            },
            level => {
                description => gettext('Category of messages that should displayed'),
                default     => 1,
                type        => 'list',
                choices     => sub {
                                    my $rmodule = main::getModule('REPORT');
                                    return undef unless($rmodule);
                                    my $erg = $rmodule->get_level_as_array();
                                    map { my $x = $_->[1]; $_->[1] = $_->[0]; $_->[0] = $x; } @$erg;
                                    return @$erg;
                                 },
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    my $rmodule = main::getModule('REPORT');
                    return undef unless($rmodule);
                    my $erg = $rmodule->get_level_as_array();
                    unless($value >= $erg->[0]->[0] and $value <= $erg->[-1]->[0]) {
                        return undef, 
                               sprintf(gettext('Sorry, but value must be between %d and %d'),
                                  $erg->[0]->[0],$erg->[-1]->[0]);
                    }
                    return $value;
                },
            },
            interval => {
                description => gettext('Time in hours to send the next mail'),
                default     => 12,
                type        => 'integer',
                required    => gettext('This is required!'),
                check       => sub {
                    my $value = int(shift) || 0;
                    if($value and ref $obj->{INTERVAL}) {
                        my $newinterval = $value*3600;
                        $obj->{INTERVAL}->interval($newinterval);
                    }
                    return $value;
                },
            },
            address => {
                description => gettext('One or more mail addresses for sending the messages'),
                default     => 'unknown@example.com, everybody@example.com',
                type        => 'string',
                required    => gettext('This is required!'),
            },
            from_address => {
                description => gettext('Mail address to describe the sender.'),
                default     => 'xxv@example.com',
                type        => 'string',
            },
            smtp => {
                description => gettext('SMTP mail server host name'),
                default     => main::getModule('STATUS')->name,
                type        => 'host',
                required    => gettext('This is required!'),
            },
            susr => {
                description => gettext('User name for mail server access'),
                default     => 'xxv',
                type        => 'string',
            },
            spwd => {
                description => gettext('Password for mail server access'),
                default     => 'xxv',
                type        => 'password',
                check       => sub{
                    my $value = shift || return;

                    return $value unless(ref $value eq 'ARRAY');

                    # If no password given the take the old password as default
                    if($value->[0] and $value->[0] ne $value->[1]) {
                        return undef, gettext("The fields with the 1st and the 2nd password must match!");
                    } else {
                        return $value->[0];
                    }
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

    # create Template object
    $self->{tt} = Template->new(
      START_TAG    => '\<\?\%',		    # Tagstyle
      END_TAG      => '\%\?\>',		    # Tagstyle
      INTERPOLATE  => 1,                # expand "$var" in plain text
      PRE_CHOMP    => 1,                # cleanup whitespace
      EVAL_PERL    => 1,                # evaluate Perl code blocks
      ABSOLUTE     => 1,
    );

    my @tmplfiles = glob(
        sprintf('%s/%s_*.tmpl',
            $self->{paths}->{NEWSTMPL},
            lc((split('::', $self->{MOD}->{Name}))[-1])
        )
    );
    for (@tmplfiles) {
        my ($order, $typ) = $_ =~ /_(\d+)_(\S+)\.tmpl$/si;
        $self->{TEMPLATES}->{$typ} = $_;
    }

    # The Initprocess
    my $erg = $self->init
        or return error("Can't initialize news modul!")
            if($self->{active} eq 'y');

    $self->{TYP} = 'text/plain';

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error('No object defined!');
    $obj->{INITE} = 1;

    $obj->{LastReportTime} = time;

    # Interval to send the next mail
    $obj->{INTERVAL} = Event->timer(
        interval => $obj->{interval}*3600,
        prio => 6,  # -1 very hard ... 6 very low
        cb => sub{
            $obj->send();
        },
    );

    $obj->{COUNT} = 1;

    1;
}

# ------------------
sub send {
# ------------------
    my $obj = shift  || return error('No object defined!');

    return error('This function is deactivated!')
        if($obj->{active} ne 'y');

    ++$obj->{COUNT};

    my $content = $obj->req();

    my $smod = main::getModule('STATUS');
    my @addresses = split(/\s*,\s*/, $obj->{address});

    # Send mail
    my $status = Mail::SendEasy::send(
        smtp => $obj->{smtp},
        user => $obj->{susr},
        pass => $obj->{spwd},
        from    => $obj->{from_address},
        from_title => 'XXV MailNewsAgent',
        to      => shift @addresses ,
        cc      => join(',', @addresses),
        subject => "News from your XXV System!" ,
        msg     => $content,
        msgid   => $obj->{COUNT},
    ) || return error sprintf("Can't send mail: %s", $Mail::SendEasy::ER);

    $obj->{LastReportTime} = time;

    lg sprintf('Mail %d. send successfully', $obj->{COUNT});
    $obj->{NEWSLETTER} = undef;
    1;
}

# ------------------
sub parseHeader {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $output = '';

    my $vars = {
        msgnr => $obj->{COUNT},
        date  => datum(time),
        anzahl=> $obj->{NEWSCOUNT},
    };

    my $template = $obj->{TEMPLATES}->{'header'};
    $obj->{tt}->process($template, $vars, \$output)
          or return error($obj->{tt}->error());

    return $output;
}

# ------------------
sub parseFooter {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $output = '';


    my $vars = {
        usage => main::getModule('RECORDS')->{CapacityMessage},
        uptime  => main::getModule('STATUS')->uptime,
        lastreport => datum($obj->{LastReportTime}),
    };

    my $template = $obj->{TEMPLATES}->{'footer'};
    $obj->{tt}->process($template, $vars, \$output)
          or return error($obj->{tt}->error());

    return $output;
}


# ------------------
sub read {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error('No data defined!');

    my $output = '';
    $vars->{count} = ++$obj->{NEWSCOUNT};
    $vars->{host}  = $obj->{host};
    $vars->{port}  = main::getModule('HTTPD')->{Port};

    my $template = $obj->{TEMPLATES}->{'content'};
    $obj->{tt}->process($template, $vars, \$output)
          or return error($obj->{tt}->error());

    $obj->{NEWSLETTER} .= $output;

    return $output;
}

# ------------------
sub req {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $test = shift  || 0;

    return gettext('The module NEWS::Mail is not active!')
        if($obj->{active} ne 'y');

    my $content = '';
    if($test) {
        $obj->send;
        $content .= gettext('A mail with the following content has been sent to your mail account!');
        $content .= "\n\n";
    }

    $content .= $obj->parseHeader();
    $content .= $obj->{NEWSLETTER};
    $content .= $obj->parseFooter();

    return $content;
}


1;
