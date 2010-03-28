package Twiggy;
use strict;
use warnings;
use 5.008_001;
our $VERSION = '0.1005';

1;
__END__

=head1 NAME

Twiggy - AnyEvent HTTP server for PSGI (like Thin)

=head1 SYNOPSIS

  twiggy --listen :8080

See C<twiggey -h> for more details.

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
renamed to Twiggy. See L</NAMING> for details.

=item Fast header parser

Uses XS/C based HTTP header parser for the best performance. (optional)

=item Lightweight and Fast

The memory required to run twiggy is 6MB and it can serve more than
4500 req/s with a single process on Perl 5.10 with MacBook Pro 13"
late 2009.

=item Superdaemon aware

Supports L<Server::Starter> for hot deploy and graceful restarts.

=back

=head1 NAMING

=head2 Twiggy?

Because it is like L<Thin|http://code.macournoyer.com/thin/>, Ruby's
Rack web server using EventMachine. You know, Twiggy is thin :)

=head2 Why the cute name instead of more descriptive namespace? Are you on drugs?

I'm sick of naming Perl software like
HTTP::Server::PSGI::How::Its::Written::With::What::Module and people
call it HSPHIWWWM on IRC. It's hard to say on speeches and newbies
would ask questions what they stand for every day. That's crazy.

This module actually includes the longer alias and an empty subclass
L<AnyEvent::Server::PSGI> for those who like to type more ::'s. It
would actually help you find this software by searching for I<PSGI
Server AnyEvent> on CPAN, which i believe is a good thing.

Yes, maybe I'm on drugs. We'll see.

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
