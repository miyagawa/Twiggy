use strict;
use warnings;
use Test::More qw(no_diag);
use Test::TCP;
use IO::Socket::INET;
use Plack::Loader;
use AnyEvent::Handle;

my $app = sub {
    my $env = shift;
    return sub {
        my ($responder, $sock) = @_;
        my $disconnected = AE::cv;
        
        # Write response after client disconnection
        my $handle = AnyEvent::Handle->new(
            fh       => $sock,
            on_read  => sub {},
            on_eof   => sub { $disconnected->send; },
            on_error => sub {},
        );
        
        $disconnected->cb(sub {
            undef $disconnected;
            undef $handle;
            shift->recv;
            $responder->([
                200,
                [ 'Content-Type' => 'text/plain', 'X_FOO' => "a" x 1_000_000 ], # Write large header to force EPIPE
                [ 'hello' ]
            ]);
        });
    }
};

my $server = Test::TCP->new(
    code => sub {
        my $port = shift;
        my $server = Plack::Loader->load("Twiggy", port => $port, host => "127.0.0.1");
        $server->run($app);
        exit; # Suppress Test::TCP "child process does not block" warning
    },
    auto_start => 1,
);

request($server->port);

kill 'QUIT' => $server->pid;
my $hanged = 0;
local $SIG{ALRM} = sub { $hanged = 1; kill 'TERM' => $server->pid; };
alarm(5);
waitpid($server->pid, 0);
alarm(0);

is $hanged, 0, "server should shut down";
done_testing();

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
    $sock->close;
}
