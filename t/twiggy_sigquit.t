# Twiggy app finishes running async request after SIGQUIT 
# but doesn't accept new connections 
use strict;
use Test::More;
use Test::Requires qw(Server::Starter LWP::UserAgent);
use Test::TCP;
use LWP::UserAgent;
use IO::Socket::INET;
use IO::Select;
use AnyEvent;
use Plack::Loader;

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;

        Plack::Loader->load( 'Twiggy', host => '127.0.0.1', port => $port )
            ->run(
            sub {
                return sub {
                    my ($responder) = @_;

                    my $w;
                    $w = AE::timer 5, 0, sub {
                        undef $w;
                        $responder->(
                            [   '200', [ 'Content-Type' => 'text/plain' ],
                                ['Hello, Twiggy!']
                            ]
                        );
                    };
                    return;
                    }
            }
            );
        exit 0;
    }
);

ok( $server, "Server started" );
my $t0    = time();
my $sock1 = request( $server->port );

kill 'QUIT' => $server->pid;
sleep(1);


# server should not accept a new connection
# after SIGQUIT
my $sock2 = IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => '127.0.0.1',
    PeerPort => $server->port,
);
if ( !$sock2 ) {
    pass("App is not listening after SIGQUIT");
}
else {
    fail("App is not listening after SIGQUIT");
    $sock2->close();
}

# the delayed request receives response
# although server is not accepting new connections
my $s = IO::Select->new();
$s->add($sock1);
my @read = $s->can_read(20);

if ( $read[0] == $sock1 ) {
    my $data;
    $sock1->recv( $data, 1024, MSG_WAITALL );
    like( $data, qr{Hello, Twiggy!}, "Response returned to \$socket1" );
    cmp_ok( time() - $t0, '>=', 5, "Response with expected delay" );
    $sock1->close();
}
else {
    fail "response not returned to \$socket1";
}

waitpid( $server->pid, 0 );
is( $?, 0, "Server quits cleanly" );


sub request {
    my $port = shift;
    my $sock = IO::Socket::INET->new(
        Proto    => 'tcp',
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    ) or die "Cannot open client socket: $!";
    $sock->autoflush;

    my $req = <<_END_;
GET / HTTP/1.0
Host: localhost:$port
User-Agent: hogehoge

_END_
    $req =~ s/\n/\r\n/g;
    $sock->print($req);
    $sock->shutdown(1); # shutdown for writing
    return $sock;
}

done_testing;
