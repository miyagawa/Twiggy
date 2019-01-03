use strict;
use warnings;

use Test::Requires qw(AnyEvent::HTTP PadWalker);
use Data::Dumper;
use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use PadWalker qw(peek_sub closed_over);
use Plack::Loader;
use POSIX ();
use Test::More;
use Test::TCP;
use Time::HiRes qw(usleep);
use Twiggy::Server;

sub exit_guard {
    my ($env) = @_;
    my $exit_guard = ${peek_sub(\&Twiggy::Server::run)->{'$self'}}->{exit_guard};
    $exit_guard->end if $env and $env->{QUERY_STRING} =~ /exit_guard_end=1/;
    $exit_guard;
}

sub do_streaming_request {
    my ( $url, $callback ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $cond = AnyEvent->condvar;

    http_get $url, timeout => 3, want_body_handle => 1, sub {
        my ( $h, $headers ) = @_;

        is $headers->{'Status'}, 200, 'streaming response should succeed';

        $h->on_read(sub {
            $h->push_read(line => sub {
                my ( undef, $line ) = @_;

                my $stop = $callback->($line, $cond);
                if($stop) {
                    $h->destroy;
                    $cond->send;
                }
            });
        });

        $h->on_error(sub {
            my ( undef, undef, $error ) = @_;

            fail "Unexpected error: $error";
            $h->destroy;
            $cond->send;
        });

        $h->on_eof(sub {
            $h->destroy;
            $cond->send;
        });
    };
    $cond->recv;
}

my $app = sub {
    my ($env) = @_;

    my $exit_guard = exit_guard($env);

    if ( $env->{PATH_INFO} eq '/basic' ) {
        [200, ['Content-Type', 'text/plain'], ["/basic"]];
    }
    elsif ( $env->{PATH_INFO} eq '/delayed' ) {
        sub {
            my $respond = shift;
            $respond->([200, ['Content-Type', 'text/plain'], ["/delayed"]]);
        };
    }
    elsif ( $env->{PATH_INFO} eq '/stream1' ) {
        my ($env) = @_;
        sub {
            my $respond = shift;
            my $writer = $respond->([200, ['Content-Type', 'text/plain']]);
            $writer->write("/stream1");
            $writer->close;
        };
    }
    elsif ( $env->{PATH_INFO} eq '/stream2' ) {
        # streaming response with small pause to respond and explicitly $writer->close
        sub {
            my $respond = shift;
            my $w; $w = AnyEvent->timer(
                after => 1,
                cb => sub {
                    my $writer = $respond->([200, ['Content-Type', 'text/plain']]);
                    $writer->write("/stream2");
                    $writer->close;
                    $w = undef;
                },
            );
        };
    }
    elsif ( $env->{PATH_INFO} eq '/stream3' ) {
        # streaming response with small pause to respond and implicitly $writer->close
        sub {
            my $respond = shift;
            my $w; $w = AnyEvent->timer(
                after => 1,
                cb => sub {
                    my $writer = $respond->([200, ['Content-Type', 'text/plain']]);
                    $writer->write("/stream3");
                    #$writer->close;
                    $w = undef;
                },
            );
        };
    }
    elsif ( $env->{PATH_INFO} eq '/vars_clean' ) {
        my $body = "/vars_clean";
        my $closed_over = closed_over(\&Twiggy::Server::_write_psgi_response);
        my $CREATED_WRITER = $closed_over->{'%CREATED_WRITER'};
        if ( keys %$CREATED_WRITER ) {
            $body = Dumper $closed_over;
        }
        [200, ['Content-Type', 'text/plain'], [$body]];
    }
    elsif ( $env->{PATH_INFO} eq '/10' ) {
        sub {
            my ( $respond ) = @_;

            my $writer = $respond->( [200, ['Content-Type', 'text/plain'] ] );

            foreach my $number ( 1 .. 10 ) {
                $writer->write($number . "\n");
                usleep 100_000;
            }
        };
    }
    else {
        [404, ['Content-Type', 'text/plain'], ["not found $env->{PATH_INFO}"]];
    }
};

{
    for my $path (qw(/basic /delayed /stream1 /stream2 /stream3)) {
        my $server = Test::TCP->new(
            code => sub {
                my ($port) = @_;
                my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
                $server->run($app);
                exit;
            },
        );
        my $port = $server->port;
        my $ua   = LWP::UserAgent->new( timeout => 2 );
        my $req  = GET ("http://localhost:$port$path?exit_guard_end=1");
        my $res  = $ua->request($req);
        is $res->content, $path, "[$path] content is good.";

        sleep 1;
        my $kid = waitpid $server->pid, POSIX::WNOHANG;
        ok $kid == $server->pid, "[$path] server terminated according to condvar.";
    }
}

{
    my $server = Test::TCP->new(
        code => sub {
            my ($port) = @_;
            my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
            $server->run($app);
        },
    );
    for my $path (qw(/basic /delayed /stream1 /stream2 /stream3 /vars_clean)) {
        my $port = $server->port;
        my $ua   = LWP::UserAgent->new( timeout => 2 );
        my $req  = GET ("http://localhost:$port$path");
        my $res  = $ua->request($req);
        is $res->content, $path, "[$path] content is good.";
    }

    do_streaming_request('http://127.0.0.1:'.$server->port.'/10', sub {
        my ( $line, $cond ) = @_;
        if($line == 5) {
            return 1;
        }
        return;
    });

    for my $path (qw(/vars_clean)) {
        my $port = $server->port;
        my $ua   = LWP::UserAgent->new( timeout => 2 );
        my $req  = GET ("http://localhost:$port$path");
        my $res  = $ua->request($req);
        is $res->content, $path, "[$path] content is good.";
    }
}

done_testing();
