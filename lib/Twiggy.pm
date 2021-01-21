package Twiggy;
use strict;
use warnings;
use 5.008_001;
our $VERSION = '0.1026';

1;
__END__

=head1 NAME

Twiggy - AnyEvent HTTP server for PSGI

=head1 SYNOPSIS

  twiggy --listen :8080

See C<twiggy -h> for more details.

  use Twiggy::Server;

  my $server = Twiggy::Server->new(
      host => $host,
      port => $port,
  );
  $server->register_service($app);

  AE::cv->recv;

=head1 DESCRIPTION

Twiggy is a lightweight and fast HTTP server with unique features such
as:

=over 4

=item PSGI

Can run any PSGI applications. Fully supports I<psgi.nonblocking> and
I<psgi.streaming> interfaces.

=item AnyEvent

This server uses AnyEvent and runs in a non-blocking event loop, so
it's best to run event-driven web applications that runs I/O bound
jobs or delayed responses such as long-poll, WebSocket or streaming
content (server push).

This software used to be called Plack::Server::AnyEvent but was
renamed to Twiggy.

=item Fast header parser

Uses XS/C based HTTP header parser for the best performance. (optional,
install the L<HTTP::Parser::XS> module to enable it; see also
L<Plack::HTTPParser> for more information).

=item Lightweight and Fast

The memory required to run twiggy is 6MB and it can serve more than
4500 req/s with a single process on Perl 5.10 with MacBook Pro 13"
late 2009.

=item Superdaemon aware

Supports L<Server::Starter> for hot deploy and graceful restarts.

To use it, instead of the usual:

    plackup --server Twiggy --port 8111 app.psgi

install L<Server::Starter> and use:

    start_server --port 8111 -- plackup --server Twiggy app.psgi

=back

=head1 ENVIRONMENT

The following environment variables are supported.

=over 4

=item TWIGGY_DEBUG

Set to true to enable debug messages from Twiggy.

=back

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=head1 AUTHOR

Tatsuhiko Miyagawa

Tokuhiro Matsuno

Yuval Kogman

Hideki Yamamura

Daisuke Maki

=head1 SEE ALSO

L<Plack> L<AnyEvent> L<Tatsumaki>

=cut
