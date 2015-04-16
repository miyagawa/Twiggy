use strict;
use warnings;

# Explicitly set loop type to pure perl loop
# because EV loop ignores SIGPIPE and produces warning only
use AnyEvent::Loop;

use Test::Requires qw(AnyEvent::HTTP);
use AnyEvent::HTTP;
use Test::More;
use Test::TCP;
use Plack::Loader;
use POSIX ();
use Time::HiRes qw(usleep);

sub do_streaming_request {
    my ( $url, $callback ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $cond = AnyEvent->condvar;

    http_get $url,
        timeout          => 3,
        want_body_handle => 1,
        sub {
            my ( $h, $headers ) = @_;

            is $headers->{'Status'}, 200, 'streaming response should succeed';

            $h->on_read(
                sub {
                    $h->push_read(
                        line => sub {
                            my ( undef, $line ) = @_;

                            my $stop = $callback->( $line, $cond );
                            if ($stop) {
                                $h->destroy;
                                $cond->send($stop);
                            }
                        }
                    );
                }
            );

            $h->on_error(
                sub {
                    my ( undef, undef, $error ) = @_;

                    fail "Unexpected error: $error";
                    $h->destroy;
                    $cond->send;
                }
            );

            $h->on_eof(
                sub {
                    $h->destroy;
                    $cond->send;
                }
            );
        };
    $cond->recv;
}

my $app = sub {
    my ( $env, $sock ) = @_;

    return sub {
        my ($respond) = @_;

        my $writer = $respond->( [ 200, [ 'Content-Type', 'text/plain' ] ] );

        my $counter = 0;
        my $tm;
        $tm = AnyEvent->timer(
            after    => 1,
            interval => 1,
            cb       => sub {
                # stream of twenty lines, every second one line 
                if ( $counter++ < 20 ) {
                    $writer->write( "Line num: $counter\n" );
                }
                else {    # stop here
                    $writer->close;
                    $tm = undef;
                }
            }
        );
    };
};

my $server = Test::TCP->new(
    code => sub {
        my ($port) = @_;

        my $server = Plack::Loader->load(
            'Twiggy',
            port => $port,
            host => '127.0.0.1'
        );
        $server->run($app);
        exit;
    },
);


my $res = do_streaming_request(
    'http://127.0.0.1:' . $server->port,
    sub {
        my ( $line, $cond ) = @_;

        # terminate client after two lines of stream
        if ( $line =~ /^Line num: 2$/ ) {
            return $line;
        }
        return;
    }
);

is ($res, 'Line num: 2', "Client finished after two lines streamed");
sleep 4;    #give the process a bit to clean up, if it died

my $kid = waitpid $server->pid, POSIX::WNOHANG;

ok $kid != $server->pid,
    'Server should stay alive after a single client breaks it connection';

done_testing();
