package XXV::OUTPUT::Ajax;

use strict;

#use Template;
use vars qw($AUTOLOAD);
use Locale::gettext;
use Tools;

$SIG{CHLD} = 'IGNORE';

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $args = {
        Name => 'Ajax',
        Prereq => {
            'XML::Simple' => 'Easy API to maintain XML (esp config files)',
            'JSON' => 'Parse and convert to JSON (JavaScript Object Notation)',
        },
        Description => gettext('This receive and send Ajax messages.'),
        Version => '0.01',
        Date => '27.10.2004',
        Author => 'xpix',
    };
    return $args;
}

# ------------------
sub AUTOLOAD {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || {};
    my $params = shift || 0;

    my $name = (split('::', $AUTOLOAD))[-1];
    return  if($name eq 'DESTROY');

    $obj->{nopack} = 1;
    $obj->out( $data, $params, $name );

    $obj->{call} = '';
}

# ------------------
sub new {
# ------------------
	my($class, %attr) = @_;
	my $self = {};
	bless($self, $class);

	# who am I
    $self->{MOD} = $self->module;

    # Try to use the Requirments
    map {
        eval "use $_";
        return panic("\nCan not load Module: $_\nPlease install this module on your System:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{handle} = $attr{'-handle'}
        || return error('No handle defined!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No TemplateDir given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No Mimehash given!');

    $self->{xml} = XML::Simple->new()
        || return error('XML failed!');

    $self->{outtype} = $attr{'-output'}
        || return error('No output type given!');

		$self->{types} = {
			'xml' => 'application/xml',
			'json' => 'text/html',
			'html' => 'text/html',
			'javascript' => 'text/javascript',
		};

		# New JSON Object if required
		if($self->{outtype} eq 'json') {
			$self->{json} = JSON->new()
				unless(ref $self->{json});
		}	

    $self->{TYP} = 'AJAX';

    $self->{CMDSTAT} = undef;

	return $self;
}

# ------------------
sub out {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || 0;
    my $para = shift || 0;
    my $name = shift || 'noName';
    my $type = shift || $obj->{types}->{$obj->{outtype}} || 'text/plain';
    my %args = @_;

    $obj->{nopack} = 1;
    unless(defined $obj->{header}) {
        # HTTP Header
        $obj->{output_header} = $obj->header($type, \%args);
    }

    $obj->{sendbytes}+= length($data);
	
		if($obj->{outtype} eq 'json') {
	    $obj->{output}->{data} = $data;
		} else {
	    $obj->{output}->{DATA} = $data;
	    $obj->{output}->{$name}->{data} = $data;
	    $obj->{output}->{$name}->{params} = $para
	        if($para);
		}
}

# ------------------
sub printout {
# ------------------
    my $obj = shift  || return error ('No Object!' );
    my $nopack = shift || $obj->{nopack} || 0;


    my $content .= ($obj->{outtype} eq 'xml' 
    								? $obj->{xml}->XMLout($obj->{output}) 
    								: 
    									( $obj->{outtype} eq 'json' 
	    									? $obj->{json}->objToJson ($obj->{output}, {pretty => 1, indent => 2})
	    									: $obj->{output}->{DATA})
									);
		# Kompress
    $content = Compress::Zlib::memGzip($content)
        if(! $nopack and $obj->{Zlib} and $obj->{browser}->{accept_gzip});

    $obj->{handle}->print($obj->{output_header}, $content);

    undef $obj->{output};
    undef $obj->{output_header};
    undef $obj->{nopack};
}


# ------------------
sub header {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $typ = shift || return error ('No Type!' );
    my $arg = shift || {};

    $arg->{'Content-encoding'} = 'gzip'
        if($obj->{browser}->{accept_gzip} && ((!defined $obj->{nopack}) || $obj->{nopack} == 0) );

    $arg->{'Cache-Control'} = 'no-cache, must-revalidate' if(!defined $arg->{'Cache-Control'});
    $arg->{'Pragma'} = 'no-cache' if(!defined $arg->{'Pragma'});

    $obj->{header} = 200;
    return $obj->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => "now",
        %{$arg},
    );
}

# ------------------
sub headerNoAuth {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $typ = shift || 'text/html';

    $obj->{header} = 401;
    return $obj->{cgi}->header(
        -type    => $typ,
        -status  => "401 Authorization Required\nWWW-Authenticate: Basic realm=\"xxvd\""
    );
}

# ------------------
sub msg {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $data = shift || 0;
    my $err  = shift || 0;


    my $msg;
    if(! $err and $data) {
        $msg = $data;
    } else {
        $msg = sprintf('ERROR:%s (%s)', $data);
    }

    $obj->out( $msg, 0, 'msg' );

    $obj->{call} = '';
}

# ------------------
sub typ {
# ------------------
    my $obj = shift || return error ('No Object!' );
    return $obj->{TYP};
}

# ------------------
sub setCall {
# ------------------
    my $obj = shift || return error ('No Object!' );
    my $name = shift || return error ('No Name!' );

    $obj->{call} = $name;
    return $obj->{call};
}

# ------------------
sub browser {
# ------------------
    my $obj = shift || return error ('No Object!' );
    return $obj->{browser};
}

1;
