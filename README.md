# NAME

Twiggy - AnyEvent HTTP server for PSGI (like Thin)

# SYNOPSIS

    twiggy --listen :8080

See `twiggy -h` for more details.

    use Twiggy::Server;

    my $server = Twiggy::Server->new(
        host => $host,
        port => $port,
    );
    $server->register_service($app);

    AE::cv->recv;

# DESCRIPTION

Twiggy is a lightweight and fast HTTP server with unique features such
as:

- PSGI

    Can run any PSGI applications. Fully supports _psgi.nonblocking_ and
    _psgi.streaming_ interfaces.

- AnyEvent

    This server uses AnyEvent and runs in a non-blocking event loop, so
    it's best to run event-driven web applications that runs I/O bound
    jobs or delayed responses such as long-poll, WebSocket or streaming
    content (server push).

    This software used to be called Plack::Server::AnyEvent but was
    renamed to Twiggy. See ["NAMING"](#NAMING) for details.

- Fast header parser

    Uses XS/C based HTTP header parser for the best performance. (optional,
    install the [HTTP::Parser::XS](http://search.cpan.org/perldoc?HTTP::Parser::XS) module to enable it; see also
    [Plack::HTTPParser](http://search.cpan.org/perldoc?Plack::HTTPParser) for more information).

- Lightweight and Fast

    The memory required to run twiggy is 6MB and it can serve more than
    4500 req/s with a single process on Perl 5.10 with MacBook Pro 13"
    late 2009.

- Superdaemon aware

    Supports [Server::Starter](http://search.cpan.org/perldoc?Server::Starter) for hot deploy and
    graceful restarts.

    To use it, instead of the usual:

        plackup --server Twiggy --port 8111 app.psgi

    install [Server::Starter](http://search.cpan.org/perldoc?Server::Starter) and use:

        start_server --port 8111 plackup --server Twiggy app.psgi



# ENVIRONMENT

The following environment variables are supported.

- TWIGGY\_DEBUG

    Set to true to enable debug messages from Twiggy.



# NAMING

## Twiggy?

Because it is like [Thin](http://code.macournoyer.com/thin/), Ruby's
Rack web server using EventMachine. You know, Twiggy is thin :)

## Why the cute name instead of more descriptive namespace? Are you on drugs?

I'm sick of naming Perl software like
HTTP::Server::PSGI::How::Its::Written::With::What::Module and people
call it HSPHIWWWM on IRC. It's hard to say on speeches and newbies
would ask questions what they stand for every day. That's crazy.

This module actually includes the longer alias and an empty subclass
[AnyEvent::Server::PSGI](http://search.cpan.org/perldoc?AnyEvent::Server::PSGI) for those who like to type more ::'s. It
would actually help you find this software by searching for _PSGI
Server AnyEvent_ on CPAN, which i believe is a good thing.

Yes, maybe I'm on drugs. We'll see.

# LICENSE

This module is licensed under the same terms as Perl itself.

# AUTHOR

Tatsuhiko Miyagawa

Tokuhiro Matsuno

Yuval Kogman

Hideki Yamamura

Daisuke Maki

# SEE ALSO

[Plack](http://search.cpan.org/perldoc?Plack) [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) [Tatsumaki](http://search.cpan.org/perldoc?Tatsumaki)
