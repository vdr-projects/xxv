package XXV::OUTPUT::NEWS::JABBER;
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
        Name => 'NEWS::JABBER',
        Prereq => {
            'Net::XMPP' => 'Jabber protocol for connect and send',
        },
        Description => gettext(qq|
This NEWS module generate a Jabber messages for your jabber client.
If come a Message from xxv with a lever >= as Preferences::level then
will this module send this Message to your jabber account
(Preferences::receiveUser).

The Problem xxv need a extra jabber account to allow to send messages in
the jabber network. This is very simple:

=over 4

=item 1 Start your jabber client, may the exodus (http://exodus.jabberstudio.org/)

=item 2 Create a new Profile with the name 'xxv'

=item 3 In the next window input following things:

    - Jabber Id: newsxxv\@jabber.org (in Example!)
    - Password:  lalala (in Example!)
    - save Password:  yes
    - new Account?:   yes

=back

Thats all!

If you want, you can test the connection to send a testmessage with
the following url in the Webinterface:

    http://vdr:8080/?cmd=request&data=jabber

or Telnet Interface:

    XXV> request jabber

Then you must receive a message in your running jabber client.

|),
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
                        or return error('Problem to initialize news module')
                            if($value eq 'y' and not exists $obj->{JCON});
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
            receiveUser => {
                description => gettext('User to be notified (as Jabber account to@jabber.server.org)'),
                default     => '',
                type        => 'string',
                required    => gettext('This is required!'),
            },
            user => {
                description => gettext('Jabber account to send message (from@jabber.server.org)'),
                default     => '',
                type        => 'string',
                required    => gettext('This is required!'),
            },
            passwd => {
                description => gettext('Password for Jabber account'),
                default     => '',
                type        => 'password',
                required    => gettext('This is required!'),
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
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{TYP} = 'text/plain';

    # Initiat after load modules ...
    main::after(sub{
        # The Initprocess
        my $erg = $self->init
            or return error('Problem to initialize news module');
    }, "NEWS::JABBER: Start initiate the Jabber module ...")
        if($self->{active} eq 'y');

	return $self;
}

# ------------------
sub init {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $url = sprintf("http://%s:%s/", $obj->{host}, main::getModule('HTTPD')->{Port});

    1;
}

# ------------------
sub jconnect {
# ------------------
    my $obj = shift  || return error('No object defined!');

    my $jcon = Net::XMPP::Client->new(
        debuglevel  =>  0,
    ) || return error('Problem to create an Jabber Client');

    my ($user, $server) = split('\@', $obj->{user});

    debug ("Connecting to jabber server: %s ...", $server);

    my @res = $jcon->Connect(
        hostname    =>  $server,
    );
    return
        unless($obj->xmpp_check_result("Connect",\@res,$jcon));

    debug ("Authentificat with User:%s ...", $user);

    @res = $jcon->AuthSend(
      'hostname'=>$server,
	  'username'=>$user,
	  'password'=>$obj->{passwd},
	  'resource'=>'xxv'
    );

    return $jcon
        if($obj->xmpp_check_result("Login",\@res,$jcon));
}

# ------------------
sub jdisconnect {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $cnx = shift  || 0;

    $cnx->Disconnect()
        if(ref $cnx);

    1;
}


# ------------------
sub send {
# ------------------
    my $obj     = shift || return error('No object defined!');
    my $vars    = shift || return error ('No Vars!' );

    return undef, lg('This function is deactivated!')
        if($obj->{active} ne 'y');

    my $cnx     = $obj->jconnect()
        || return error ('No connected JabberClient!' );

    $cnx->MessageSend(
        'to'     => $obj->{receiveUser},
        'subject'=> $vars->{Title},
        'body'   => ($vars->{Text} || $vars->{Url}),
    );

    $cnx = $obj->jdisconnect($cnx);

    1;
}

# ------------------
sub read {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my $vars = shift || return error ('No News!' );

    return $obj->send($vars);

    1;
}

# ------------------
sub req {
# ------------------
    my $obj = shift  || return error('No object defined!');

    return gettext('The module NEWS::JABBER is not active!')
        if($obj->{active} ne 'y');

    my $vars = {
        AddDate => time,
        Title   => 'This is a testmessage for NEWS::JABBER ...',
        Text    => "abcdefghijklmnopqrstuvwxyz\nABCDEFGHIJKLMNOPQRSTUVWXYZ\n0123456789\n‰¸ˆƒ‹÷!@#$%^&*()_+=-':;<>?/\n",
        Level   => 100,
    };

    if($obj->send($vars)) {
        return sprintf('Message is send to %s at %s', $obj->{receiveUser}, datum($vars->{AddDate}, 'voll'));
    } else {
        return sprintf('Upps, problem send Message to %s at %s', $obj->{receiveUser}, datum($vars->{AddDate}, 'voll'));
    }
}

# ------------------
sub xmpp_check_result {
# ------------------
    my $obj = shift  || return error('No object defined!');
    my ($txt,$res,$cnx)=@_;

    return error("Error '$txt': result undefined")
	    unless($res);

    # result can be true or 'ok'
    if ((@$res == 1 && $$res[0]) || $$res[0] eq 'ok') {
	    return debug "%s: %s", $txt, $$res[0];
    # otherwise, there is some error
    } else {
	    my $errmsg = $cnx->GetErrorCode() || '?';
        $cnx->Disconnect();
	    return error("Error %s: %s [%s]", $txt, join (': ',@$res), $errmsg);
    }
}

1;
