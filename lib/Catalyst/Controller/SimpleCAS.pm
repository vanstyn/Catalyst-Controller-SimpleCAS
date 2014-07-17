package Catalyst::Controller::SimpleCAS;
use strict;
use warnings;

# ABSTRACT: General-purpose content-addressed storage (CAS) for Catalyst

our $VERSION = 0.01;

use Moose;
use namespace::autoclean;
require Module::Runtime;

BEGIN { extends 'Catalyst::Controller' }




1;


__END__

=head1 NAME

Catalyst::Controller::SimpleCAS - General-purpose content-addressed storage (CAS) module

=head1 SYNOPSIS

 use Catalyst::Controller::SimpleCAS;
 ...

=head1 DESCRIPTION

This controller provides a simple content-addressed storage backend for Catalyst applications. 

This module was originally developed within L<RapidApp> before being extracted into its own module.


=head1 SEE ALSO

=over

=item *

L<Catalyst>

=item *

L<Catalyst::Controller>

=item * 

L<RapidApp>

=back

=head1 AUTHOR

Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by IntelliTree Solutions llc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
