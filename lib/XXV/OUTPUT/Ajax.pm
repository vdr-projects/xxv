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
    my $self = shift || return error('No object defined!');
    my $args = {
        Name => 'Ajax',
        Prereq => {
            'XML::Simple' => 'Easy API to maintain XML (esp config files)',
            'JSON' => 'Parse and convert to JSON (JavaScript Object Notation)',
        },
        Description => gettext('This receive and send Ajax messages.'),
        Version => (split(/ /, '$Revision$'))[1],
        Date => (split(/ /, '$Date$'))[1],
        Author => 'xpix',
        LastAuthor => (split(/ /, '$Author$'))[1],
    };
    return $args;
}

# ------------------
sub AUTOLOAD {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || {};
    my $params = shift || 0;

    my $name = (split('::', $AUTOLOAD))[-1];
    return  if($name eq 'DESTROY');

    $self->{nopack} = 1;
    $self->out( $data, $params, $name );

    $self->{call} = '';
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
        return panic("\nCouldn't load modul: $_\nPlease install this modul on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{handle} = $attr{'-handle'}
        || return error('No handle defined!');

    $self->{cgi} = $attr{'-cgi'}
        || return error('No cgi given!');

    $self->{browser} = $attr{'-browser'}
        || return error('No browser given!');

    $self->{outtype} = $attr{'-output'}
        || return error('No output type given!');

		$self->{types} = {
			'xml' => 'application/xml',
#			'json' => 'application/json; charset=utf-8', # json with utf-8
#			'json' => 'application/json; charset=iso-8859-1', # json with iso-8859
			'json' => 'text/html',
			'text' => 'text/plain',
		};

		# New JSON Object if required
		if($self->{outtype} eq 'json') {
			$self->{json} = JSON->new()
        || return error("Can't create JSON instance!");
		}	elsif($self->{outtype} eq 'xml') {
      $self->{xml} = XML::Simple->new()
        || return error("Can't create XML instance!");
    }	elsif($self->{outtype} eq 'text') {
        # ...
    } else {
       $self->{outtype} = 'text';
#      return error(sprintf("Can't create instance for typ '%s'!"),$self->{outtype});
    }
    $self->{TYP} = 'AJAX';

	return $self;
}

# ------------------
sub out {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || 0;
    my $para = shift || 0;
    my $name = shift || 'noName';
    my $type = shift || $self->{types}->{$self->{outtype}} || 'text/plain';
    my %args = @_;

    $self->{nopack} = 1;
    unless(defined $self->{header}) {
        # HTTP Header
        $self->{output_header} = $self->header($type, \%args);
    }

    $self->{sendbytes}+= length($data);
	
		if($type ne 'application/xml') {
	    $self->{output}->{data} = $data;
		} else {
	    $self->{output}->{DATA} = $data;
	    $self->{output}->{$name}->{data} = $data;
	    $self->{output}->{$name}->{params} = $para
	        if($para);
		}
}

# ------------------
sub printout {
# ------------------
    my $self = shift  || return error('No object defined!');
    my $nopack = shift || $self->{nopack} || 0;

    my $content;
    if($self->{browser}->{Method} ne 'HEAD') {
      if( $self->{outtype} eq 'json' ) {
        if($self->{json}->can('to_json')) { # Version 2.0 see http://search.cpan.org/~makamaka/JSON-2.04/lib/JSON.pm#Transition_ways_from_1.xx_to_2.xx.
          $content = $self->{json}->to_json($self->{output});
        } else { # Version 1.0
          $content = $self->{json}->objToJson($self->{output});
        }
      } elsif($self->{outtype} eq 'xml') {
        $content = $self->{xml}->XMLout($self->{output});
      } else {
        $content = $self->{output}->{data};
      }

	  	# compress data
      $content = Compress::Zlib::memGzip($content)
        if(! $nopack and $self->{Zlib} and $self->{browser}->{accept_gzip});
    }

    if($content) {
      $self->{handle}->print($self->{output_header},$content);
      $self->{sendbytes}+= length($self->{output_header});
      $self->{sendbytes}+= length($content);
    } else {
      $self->{handle}->print($self->{output_header});
      $self->{sendbytes}+= length($self->{output_header});
    }

    undef $self->{output};
    undef $self->{output_header};
    undef $self->{nopack};
}


# ------------------
sub header {
# ------------------
    my $self = shift || return error('No object defined!');
    my $typ = shift || return error('No type defined!');
    my $arg = shift || {};

    $arg->{'Content-encoding'} = 'gzip'
        if($self->{browser}->{accept_gzip} && ((!defined $self->{nopack}) || $self->{nopack} == 0) );

    $arg->{'Cache-Control'} = 'no-cache, must-revalidate' if(!defined $arg->{'Cache-Control'});
    $arg->{'Pragma'} = 'no-cache' if(!defined $arg->{'Pragma'});

    $self->{header} = 200;
    return $self->{cgi}->header(
        -type   =>  $typ,
        -status  => "200 OK",
        -expires => "now",
        %{$arg},
    );
}

# ------------------
sub headerNoAuth {
# ------------------
    my $self = shift || return error('No object defined!');
    my $typ = shift || 'text/html';

    $self->{header} = 401;
    return $self->{cgi}->header(
        -type    => $typ,
        -status  => "401 Authorization Required\nWWW-Authenticate: Basic realm=\"xxvd\""
    );
}

# ------------------
sub msg {
# ------------------
    my $self = shift || return error('No object defined!');
    my $data = shift || 0;
    my $err  = shift || 0;


    my $msg;
    if(! $err and $data) {
        $msg = $data;
    } else {
        $msg = sprintf('ERROR:%s (%s)', $data);
    }

    $self->out( $msg, 0, 'msg' );

    $self->{call} = '';
}

# ------------------
sub typ {
# ------------------
    my $self = shift || return error('No object defined!');
    return $self->{TYP};
}

# ------------------
sub setCall {
# ------------------
    my $self = shift || return error('No object defined!');
    my $name = shift || return error('No name defined!');

    $self->{call} = $name;
    return $self->{call};
}

# ------------------
sub browser {
# ------------------
    my $self = shift || return error('No object defined!');
    return $self->{browser};
}

1;
