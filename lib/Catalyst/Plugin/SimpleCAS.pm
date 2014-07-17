package Catalyst::Plugin::SimpleCAS;
use strict;
use warnings;

our $VERSION = 0.01;

use Moose::Role;
use namespace::autoclean;

use CatalystX::InjectComponent;
use Catalyst::Controller::SimpleCAS;



1;

__END__

=pod

=head1 NAME

Catalyst::Plugin::SimpleCAS - Plugin interface to L<Catalyst::Controller::SimpleCAS>

=head1 SYNOPSIS

  use Catalyst qw(SimpleCAS);
  ...

=head1 DESCRIPTION

This class provides a simple Catalyst Plugin interface to L<Catalyst::Controller::SimpleCAS>. 


=head1 SEE ALSO

=over

=item L<Catalyst::Controller::SimpleCAS>

=back


=head1 AUTHOR

Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by IntelliTree Solutions llc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
