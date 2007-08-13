package XXV::OUTPUT::HTML::PUSH;

use strict;

use Tools;

$| = 1;

=head1 NAME

XXV::OUTPUT::HTML::PUSH - A Push for http system

=head1 SYNOPSIS

    use XXV::OUTPUT::HTML::PUSH;

    my $pusher =  XXV::OUTPUT::HTML::PUSH->new(
        -cgi => $obj->{cgi},        # The CGI Object from Lincoln Stein
        -handle => $obj->{handle},  # The handle to printout the http Stuff
    );

    $pusher->start();       # Start the Push Process

    while($c > 10) {
        $pusher->print($c++);  # Print out the message
    }

    $pusher->stop();        # Stop the Push


=cut

# ------------------
sub new {
# ------------------
	my($class, %attr) = @_;
	my $self = {};
	bless($self, $class);

    $self->{handle} = $attr{'-handle'}
        || return error('No handle defined!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No CGI Object defined!');

	return $self;
}

# ------------------
sub start {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $out = shift ||  0;
    $obj->{handle}->print($obj->{cgi}->multipart_init(-boundary=>'----here we go!'));
    $obj->print($out) if($out);
}

# ------------------
sub print {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $msg = shift  || return;
    my $type = shift || 'text/html';

    $obj->{handle}->print($obj->{cgi}->multipart_start(-type=>$type));
    $obj->{handle}->print($msg."\n");
    $obj->{handle}->print($obj->{cgi}->multipart_end);
}

# ------------------
sub follow_print {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $msg = shift  || return;
    my $type = shift || 'text/html';

    unless($obj->{header}) {
        $obj->{handle}->print($obj->{cgi}->multipart_start(-type=>$type));
        $obj->{header} = 1;
    }
    $obj->{handle}->print($msg."\n");
}

# ------------------
sub stop {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    $obj->{handle}->print($obj->{cgi}->multipart_end);
    $obj->{handle}->print($obj->{cgi}->header(
        -type   =>  'text/html',
        -status  => "200 OK",
    ));
}

1;
