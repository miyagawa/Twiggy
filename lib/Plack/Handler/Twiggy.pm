package Plack::Handler::Twiggy;
use strict;
use parent qw( AnyEvent::Server::PSGI::Twiggy );

1;

__END__

=head1 NAME

Plack::Handler::Twiggy - Adapter for Twiggy

=head1 SYNOPSIS

  plackup -s Twiggy --port 9090

=head1 DESCRIPTION

This is an adapter to run PSGI apps on Twiggy via L<plackup>.

=hea1 SEE ALSO

L<plackup>

=cut

