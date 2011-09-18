use strict;
use warnings;
use Test::More qw(no_diag);
use Test::TCP;
use IO::Socket::INET;
use Plack::Loader;
use Plack::Request;
use HTTP::Response;

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $params = $req->parameters;

    return [
        200,
        [ 'Content-Type' => 'text/plain', ],
        [ $params->{q} ],
    ];
};

# test that client disconnection doesn't trigger 400 response

test_tcp(
    client => sub {
        my $port = shift;

        # empty request
        my $sock = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        ) or die "Cannot open client socket: $!";
        $sock->shutdown(1);

        my $data = join('', <$sock>);
        $sock->close;

        is($data, '', 'got empty response to empty request')
            or note explain $data;

        # incomplete headers
        $sock = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        ) or die "Cannot open client socket: $!";

        print $sock "GET / HTTP/1.0"; # no CRLF
        $sock->shutdown(1);

        $data = join('', <$sock>);
        $sock->close;

        is($data, '', 'got empty response to incomplete header request')
            or note explain $data;
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
        $server->run($app);
    },
);

done_testing();
