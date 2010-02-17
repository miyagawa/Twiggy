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

test_tcp(
    client => sub {
        my $port = shift;

        my @bytes_list = (100, 10_000, 1_000_000);

        foreach my $bytes (@bytes_list) {
            post_request($port, $bytes, 0);
        }

        foreach my $bytes (@bytes_list) {
            post_request($port, $bytes, 0.1);
        }
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
        $server->run($app);
    },
);

test_tcp(
    client => sub {
        my $port = shift;

        my @bytes_list = (100, 10_000, 1_000_000);

        foreach my $bytes (@bytes_list) {
            post_request($port, $bytes, 0);
        }

        foreach my $bytes (@bytes_list) {
            post_request($port, $bytes, 0.1);
        }
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1', workers => 5);
        $server->run($app);
    },
);

done_testing();


sub post_request {
    my ($port, $bytes, $wait) = @_;

    my $sock = IO::Socket::INET->new(
        Proto => 'tcp',
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    ) or die "Cannot open client socket: $!";
    $sock->autoflush;

    my $post_body = 'q=' . 'x' x $bytes;

    my $req = <<_END_;
POST / HTTP/1.0
Host: localhost:$port
User-Agent: hogehoge
Content-Type: application/x-www-form-urlencoded
Content-Length: @{[ length $post_body ]}

_END_
    $req =~ s/\n/\r\n/g;

    $sock->print($req);

    select(undef, undef, undef, $wait) if $wait;

    $sock->print($post_body);

    my $res = HTTP::Response->parse(join('', <$sock>));
    $sock->close;

    is $res->code, 200, "bytes=$bytes, wait=$wait";
    is $res->content, 'x' x $bytes;
}
