use strict;
use warnings;
use FindBin;
use Test::More;
use Test::Requires qw(AnyEvent HTTP::Parser::XS);

use Plack;
use Plack::Test::Suite;

use HTTP::Request;
use HTTP::Request::Common;

local @Plack::Test::Suite::TEST = (
    [
        'CondVar',
        sub {
            my $cb = shift;
            my $res = $cb->(GET "http://127.0.0.1/?name=miyagawa");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=miyagawa';
        },
        sub {
            my $env = shift;

            my $cv = AE::cv;

            $cv->send([
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ 'Hello, ' . $env->{QUERY_STRING} ],
            ]);

            return $cv;
        },
    ],
    [
        'coderef res',
        sub {
            my $cb = shift;
            my $res = $cb->(GET "http://127.0.0.1/?name=miyagawa");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=miyagawa';
        },
        sub {
            my $env = shift;

            return sub {
                my ( $write, $sock ) = @_;

                $write->([
                    200,
                    [ 'Content-Type' => 'text/plain', ],
                    [ 'Hello, ' . $env->{QUERY_STRING} ],
                ]);
            }
        },
    ],
    [
        'coderef streaming',
        sub {
            my $cb = shift;
            my $res = $cb->(GET "http://127.0.0.1/?name=miyagawa");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=miyagawa';
        },
        sub {
            my $env = shift;

            return sub {
                my ( $write, $sock ) = @_;

                my $writer = $write->([
                    200,
                    [ 'Content-Type' => 'text/plain', ],
                ]);

                $writer->write("Hello, ");
                $writer->write($env->{QUERY_STRING});
                $writer->close();
            }
        },
    ],
    [
        'coderef poll_cb',
        sub {
            my $cb = shift;
            my $res = $cb->(GET "http://127.0.0.1/?name=miyagawa");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=miyagawa';
        },
        sub {
            my $env = shift;

            return sub {
                my ( $write, $sock ) = @_;

                my @queue = ( "Hello, ", $env->{QUERY_STRING} );

                my $w = $write->([
                    200,
                    [ 'Content-Type' => 'text/plain' ],
                ]);
                $w->poll_cb(sub {
                    my $writer = shift;

                    if ( @queue ) {
                        $writer->write(shift @queue);
                    } else {
                        $writer->close;
                    }
                });
            };
        },
    ]
);

# prevent Lint middleware from being used
Plack::Test::Suite->run_server_tests(sub {
    my($port, $app) = @_;
    my $server = Plack::Loader->load("AnyEvent", port => $port, host => "127.0.0.1");
    $server->run($app);
});

done_testing();

