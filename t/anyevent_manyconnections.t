use strict;
use warnings;
use Test::More;

BEGIN {
    plan skip_all => 'Slow test skipped unless $ENV{TEST_SLOW} is set'
        unless $ENV{TEST_SLOW};
}

use Plack::Test::Suite;
use AnyEvent;

use HTTP::Request;
use HTTP::Request::Common;

my $LOOPS = 1024; # Default max fds on linux.

sub gentest {
    my $name = shift;
    return ($name, sub {
        my $cb = shift;
        for (1..$LOOPS) {
            alarm 2;
            local $SIG{ALRM} = sub {
                fail("Timed out");
                exit;
            };
            my $res = $cb->(GET "http://127.0.0.1/");
            is $res->code, 200, "$name $_ of $LOOPS";
            alarm 0;
        }
    });
}

local @Plack::Test::Suite::TEST = (
    [
        gentest('BadResponse'),
        sub {
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                'Hello'
            ];
        },
    ],
    [
        gentest('GoodResponse'),
        sub {
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                ['Hello']
            ];
        },
    ],
);

# prevent Lint middleware from being used
Plack::Test::Suite->run_server_tests(sub {
    my($port, $app) = @_;
    my $server = Plack::Loader->load("Twiggy", port => $port, host => "127.0.0.1");
    $server->run($app);
});

done_testing();

