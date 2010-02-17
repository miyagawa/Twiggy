use strict;
use warnings;
use Test::More qw(no_diag);
use Test::TCP;
use IO::Socket::INET;
use Plack::Loader;
use Plack::Request;
use HTTP::Response;
use LWP::UserAgent;

my $count = 0;
my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $params = $req->parameters;

    $count++;

    return [
        200,
        [ 'Content-Type' => 'text/plain', ],
        [ $count ],
    ];
};

my $max = 10;
test_tcp(
    client => sub {
        my $port = shift;
        my $ua = LWP::UserAgent->new();

        for (1..$max) {
            my $res = $ua->get("http://127.0.0.1:$port/");
            ok( $res->is_success, "request #$_" );
            ok( $res->content <= $max, "got " . $res->content );
        }
        sleep 2;

        # XXX we should get here a refreshed child, so content should start
        # from 1
        my $res = $ua->get("http://127.0.0.1:$port/");
        ok( $res->is_success, "request #" . ($max + 1) );
        is( $res->content, 1, "got " . $res->content );
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1', workers => 1, max_requests => $max);
        $server->run($app);
    },
);

done_testing();
