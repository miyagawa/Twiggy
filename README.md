# NAME

Twiggy - AnyEvent HTTP server for PSGI

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
    renamed to Twiggy.

- Fast header parser

    Uses XS/C based HTTP header parser for the best performance. (optional,
    install the [HTTP::Parser::XS](https://metacpan.org/pod/HTTP::Parser::XS) module to enable it; see also
    [Plack::HTTPParser](https://metacpan.org/pod/Plack::HTTPParser) for more information).

- Lightweight and Fast

    The memory required to run twiggy is 6MB and it can serve more than
    4500 req/s with a single process on Perl 5.10 with MacBook Pro 13"
    late 2009.

- Superdaemon aware

    Supports [Server::Starter](https://metacpan.org/pod/Server::Starter) for hot deploy and graceful restarts.

    To use it, instead of the usual:

        plackup --server Twiggy --port 8111 app.psgi

    install [Server::Starter](https://metacpan.org/pod/Server::Starter) and use:

        start_server --port 8111 -- plackup --server Twiggy app.psgi

# ENVIRONMENT

The following environment variables are supported.

- TWIGGY\_DEBUG

    Set to true to enable debug messages from Twiggy.

# LICENSE

This module is licensed under the same terms as Perl itself.

# AUTHOR

Tatsuhiko Miyagawa

Tokuhiro Matsuno

Yuval Kogman

Hideki Yamamura

Daisuke Maki

# SEE ALSO

[Plack](https://metacpan.org/pod/Plack) [AnyEvent](https://metacpan.org/pod/AnyEvent) [Tatsumaki](https://metacpan.org/pod/Tatsumaki)
