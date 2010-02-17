use strict;
use Test::More;
use Test::Requires qw(Server::Starter);
use Test::TCP;
use LWP::UserAgent;
use Server::Starter qw(start_server);

test_tcp(
    server => sub {
        my $port = shift;

        start_server(
            exec => [ $^X, '-Mblib', '-MPlack::Loader', '-e',
                q|Plack::Loader->load('Twiggy', host => '127.0.0.1')->run(sub { [ '200', ['Content-Type' => 'text/plain'], [ 'Hello, Twiggy!' ] ] })| ],
            port => [ $port ]
        );
        exit 1;
    },
    client => sub {
        my $port = shift;

        # XXX LWP is implied by plack
        my $ua = LWP::UserAgent->new();
        my $res = $ua->get("http://127.0.0.1:$port/");
        ok $res->is_success, "request ok";
        is $res->content, "Hello, Twiggy!";
    }
);

test_tcp(
    server => sub {
        my $port = shift;

        start_server(
            exec => [ $^X, '-Mblib', '-MPlack::Loader', '-e',
                q|Plack::Loader->load('Twiggy', host => '127.0.0.1', workers => 5)->run(sub { [ '200', ['Content-Type' => 'text/plain'], [ 'Hello, Twiggy!' ] ] })| ],
            port => [ $port ]
        );
        exit 1;
    },
    client => sub {
        my $port = shift;

        # XXX LWP is implied by plack
        my $ua = LWP::UserAgent->new();
        my $res = $ua->get("http://127.0.0.1:$port/");
        ok $res->is_success, "request ok";
        is $res->content, "Hello, Twiggy!";
    }
);

done_testing;
