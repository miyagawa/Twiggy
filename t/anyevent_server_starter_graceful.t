# Test of gaceful restart with Server::Starter
# After SIGQUIT a new worker is spawned, old worker
# finishes old requests but doesn't accept new ones
use strict;
use Test::More;
use Test::Requires qw(Server::Starter LWP::UserAgent);
use Test::TCP;
use LWP::UserAgent;
use IO::Socket::INET;
use IO::Select;
use Server::Starter qw/start_server/;

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;

        start_server(
            signal_on_hup => 'QUIT',
            port          => [$port],
            exec          => [
                $^X,          '-Mblib',
                '-MAnyEvent', '-MPlack::Loader',
                '-e',         <<'_APP' ],
        Plack::Loader->load( 'Twiggy', host => '127.0.0.1' )
            ->run(
            sub {
                my $env = shift;

                my (undef, $sockname, $delay) = split('/', $env->{REQUEST_URI});

                return sub {
                    my ($responder) = @_;

                    my $w;
                    $w = AE::timer $delay, 0, sub {
                        undef $w;
                        $responder->(
                            [   '200', [ 'Content-Type' => 'text/plain' ],
                                ["Sockname: $sockname\nPID: $$"]
                            ]
                        );
                    };
                    return;
                    }
            }
            );
_APP
        );
        exit 0;
    }
);

ok( $server, "Server started" );

sleep(2);  # let the server start

my @clients;

# first request with delayed response for 10 seconds
$clients[0] =  {
    socket => request( $server->port, 'sock0', 10 ),
    t0 => time()
};    

sleep (1);

# graceful restart
kill 'HUP' => $server->pid;

sleep(2); # let child start

# second "client" should connect to a new instance
$clients[1] =  {
    socket => request( $server->port, 'sock1', 2 ),
    t0 => time()
};    



# wait for responses
read_responses( \@clients );

# clients should be served from different workers
cmp_ok(
    $clients[0]->{pid},
    '!=',
    $clients[1]->{pid},
    "Requests served with different workers"
);
cmp_ok( $clients[0]->{delay}, '>=', 10, "First request served last" );
cmp_ok( $clients[1]->{delay}, '>=', 2,
    "Second request served first" );

# kill server
kill 'TERM' => $server->pid;
waitpid( $server->pid, 0 );
is( $?, 0, "Server quits cleanly" );




sub request {
    my ( $port, $sockname, $delay ) = @_;
    my $sock = IO::Socket::INET->new(
        Proto    => 'tcp',
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    ) or die "Cannot open client socket: $!";
    $sock->autoflush;

    my $req = <<_END_;
GET /$sockname/$delay HTTP/1.0
Host: localhost:$port
User-Agent: hogehoge

_END_
    $req =~ s/\n/\r\n/g;
    $sock->print($req) or die "Can't write to socket: $!";
    $sock->shutdown(1);    # close for writing
    return $sock;
}


sub read_responses {
    my ($clients) = @_;

    my @sockets = map { $_->{socket} } @$clients ;
    my $select = IO::Select->new( @sockets );

    while ( my @read = $select->can_read(20) ) {
        for my $s (@read) {
            $s->recv( my $data, 1024, MSG_WAITALL );

            my ($p)        = $data =~ /^PID: (\d+)/m;
            my ($sockname) = $data =~ /^Sockname: (\S+)/m;

            my ($c) = grep { $_->{socket} == $s } @$clients; 
            my $delay = time() - $c->{t0};
            ok( $p, "Pid returned ($p) for $sockname after $delay sec" );
            $c->{pid} = $p;
            $c->{delay} = $delay;
            $select->remove($s);
            $s->close;
        }
    }

    is($select->count, 0, "All sockets read");

}

done_testing;
