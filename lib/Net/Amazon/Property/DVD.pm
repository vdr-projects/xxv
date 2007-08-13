######################################################################
package Net::Amazon::Property::DVD;
######################################################################
use warnings;
use strict;
use base qw(Net::Amazon::Property);

__PACKAGE__->make_accessor($_) for qw(title studio theatrical_release_date
  media nummedia upc mpaa_rating);
__PACKAGE__->make_array_accessor($_) for qw(directors starring features);

##################################################
sub new {
##################################################
    my($class, %options) = @_;

    my $self = $class->SUPER::new(%options);
    bless $self, $class; # Bless into this class

    if(exists $options{xmlref}) {
        $self->init_via_xmlref($options{xmlref});
    }

    return $self;
}

##################################################
sub director {
##################################################
    my($self, $nameref) = @_;

    # Only return the first director
    return ($self->directors($nameref))[0];
}

##################################################
sub init_via_xmlref {
##################################################
    my($self, $xmlref) = @_;

    $self->SUPER::init_via_xmlref($xmlref);

    $self->title($xmlref->{ProductName});
    $self->studio($xmlref->{Manufacturer});
    $self->directors($xmlref->{Directors}->{Director});
    $self->starring($xmlref->{Starring}->{Actor});
    $self->media($xmlref->{Media});
    $self->nummedia($xmlref->{NumMedia});
    $self->upc($xmlref->{Upc});
    $self->theatrical_release_date($xmlref->{TheatricalReleaseDate});
    $self->mpaa_rating($xmlref->{MpaaRating});
    $self->features($xmlref->{Features}->{Feature});
}

1;

__END__

=head1 NAME

Net::Amazon::Property::DVD - Class for DVDs on amazon.com

=head1 SYNOPSIS

  use Net::Amazon;

  # ...

  if($resp->is_success()) {
      for my $prop ($resp->properties) {
          print $_->title(), " ",
                $_->studio(), " ",
                $_->year(), "\n";
  }

=head1 DESCRIPTION

C<Net::Amazon::Property::DVD> is derived from 
C<Net::Amazon::Property> and on top of the all-purpose
methods the base class provides, it offers specialized accessors for
DVD parameters.

=head2 METHODS

=over 4

=item title()

Returns the title of the DVD.

=item studio()

Returns the studio.

=item directors()

Returns a list of directors. Note that there's also a director() method
only returning the first director.

=item starring()

Returns a list of actors starring in the movie.

=item upc()

Returns the DVD's UPC as a string.

=item media()

Returns the DVD's media type as a string.

=item nummedia()

Returns the DVD's number of media (number of discs) as a string.
Amazon doesn't always send this back, so if you get undef assume it
is 1.

=item theatrical_release_date()

Returns the DVD's theatrical release date.

=item mpaa_rating()

Returns the DVD's MPAA rating.

=item features()

Returns the DVD's features as a list of strings. Examples: 
"Color", "Closed-captioned", "Widescreen".

=item new(xmlref => $xmlref)

Initializes an object by passing a hash of hashes structure containing
the XML data returned from the service. Usually, this is just used by
C<Net::Amazon> internally to initialize objects for on backcoming
data.

=back

Check out L<Net::Amazon::Property> for all-purpose accessors, like
C<year>, C<OurPrice>, C<ListPrice>, etc.

=head1 SEE ALSO

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Mike Schilli E<lt>m@perlmeister.comE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
