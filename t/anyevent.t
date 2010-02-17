use strict;
use warnings;
use FindBin;
use Test::More;
use Test::Requires qw(AnyEvent HTTP::Parser::XS);

use Plack;
use Plack::Test::Suite;

Plack::Test::Suite->run_server_tests('Twiggy');
Plack::Test::Suite->run_server_tests('Twiggy', undef, undef, workers => 5);
done_testing();
