use strict;
use warnings;

use Test::Requires qw(AnyEvent::HTTP PadWalker);
use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use PadWalker qw(peek_sub);
use Plack::Loader;
use POSIX ();
use Test::More;
use Test::TCP;

sub exit_guard_end {
    my $exit_guard = ${peek_sub(\&Twiggy::Server::run)->{'$self'}}->{exit_guard};
    $exit_guard->end;
}

sub test {
    my ($app_name, $app) = @_;
    my $server = Test::TCP->new(
        code => sub {
            my ($port) = @_;
            my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
            $server->run($app);
            exit;
        },
    );
    {
        my $port = $server->port;
        my $ua   = LWP::UserAgent->new( timeout => 2 );
        my $req  = GET ("http://localhost:$port/");
        my $res  = $ua->request($req);
        is $res->content, $app_name, "[$app_name] content is good.";

        sleep 1;
        my $kid = waitpid $server->pid, POSIX::WNOHANG;
        ok $kid == $server->pid, "[$app_name] server terminated according to condvar.";
    }
}

test(
    "basic response",
    sub {
        exit_guard_end();
        [200, ['Content-Type', 'text/plain'], ["basic response"]];
    },
);

test(
    "delayed response",
    sub {
        my ($env) = @_;
        sub {
            my $respond = shift;
            exit_guard_end();
            $respond->([200, ['Content-Type', 'text/plain'], ["delayed response"]]);
        };
    },
);

test(
    "streaming response",
    sub {
        my ($env) = @_;
        sub {
            my $respond = shift;
            my $writer = $respond->([200, ['Content-Type', 'text/plain']]);
            $writer->write("streaming response");
            exit_guard_end();
            $writer->close;
        };
    },
);

test(
    "streaming response with small pause to respond",
    sub {
        my ($env) = @_;
        sub {
            my $respond = shift;
            my $w; $w = AnyEvent->timer(
                after => 1,
                cb => sub {
                    my $writer = $respond->([200, ['Content-Type', 'text/plain']]);
                    $writer->write("streaming response with small pause to respond");
                    exit_guard_end();
                    $writer->close;
                    $w = undef;
                },
            );
        };
    },
);

done_testing();
