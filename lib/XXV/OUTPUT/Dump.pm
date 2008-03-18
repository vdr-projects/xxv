package XXV::OUTPUT::Dump;

use strict;

use vars qw($AUTOLOAD);
use Tools;

# This module method must exist for XXV
# ------------------
sub module {
# ------------------
    my $obj = shift || return error('No object defined!');
    my $args = {
        Name => 'Dump',
        Prereq => {
        },
        Description => gettext('This receives and sends dump messages.'),
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
    my $obj = shift || return error('No object defined!');

    return if($AUTOLOAD =~ /DESTROY$/);
dumper(\@_);
    return @_;
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
        return panic("\nCouldn't load perl module: $_\nPlease install this module on your system:\nperl -MCPAN -e 'install $_'") if($@);
    } keys %{$self->{MOD}->{Prereq}};

    $self->{TYP} = 'INTERFACE';

	return $self;
}

# ------------------
sub typ {
# ------------------
    my $obj = shift || return error('No object defined!');
    return $obj->{TYP};
}

1;
