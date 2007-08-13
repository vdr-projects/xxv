######################################################################
package Net::Amazon::Request::Seller;
######################################################################
use base qw(Net::Amazon::Request);

##################################################
sub new {
##################################################
    my($class, %options) = @_;

    if(exists $options{seller}) {
        $options{SellerSearch} = $options{seller};
        delete $options{seller};
    } else {
        die "Mandatory parameter 'seller' not defined";
    }

    my $self = $class->SUPER::new(%options);

    bless $self, $class;   # reconsecrate
}

1;

__END__

=head1 NAME

Net::Amazon::Request::Seller - Class for submitting Seller requests

=head1 SYNOPSIS

  use Net::Amazon;
  use Net::Amazon::Request::Seller;

  my $ua = Net::Amazon->new(
      token       => 'YOUR_AMZN_TOKEN'
  );

  my $req = Net::Amazon::Request::Seller->new( 
      seller  => 'A2GXAGU54VOP7'
  );

    # Response is of type Net::Amazon::Response::Seller
  my $resp = $ua->request($req);

=head1 DESCRIPTION

C<Net::Amazon::Request::Seller> is a class used to submit Seller search
requests to the Amazon web service.

The seller to search for is specified in the C<seller> parameter, which
contains the seller's ID (not the seller's nickname!).

Upon success, the responses' C<result()> method will return a single
C<Net::Amazon::Result::Seller> object.

Check L<Net::Amazon::Request> for common request parameters not listed here.

=head2 METHODS

=over 4

=item new( seller => $seller_id )

Constructs a new C<Net::Amazon::Request::Seller> object, used to query
the Amazon web service with the given seller id.

=back

=head1 SEE ALSO

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Mike Schilli E<lt>m@perlmeister.comE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
