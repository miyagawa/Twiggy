use strict;
use warnings;
use Test::More qw(no_diag);
use Test::Requires qw( Plack::Middleware::Deflater LWP::UserAgent IO::Uncompress::Gunzip );
use Test::TCP;
use Plack::Loader;
use Plack::Request;
use HTTP::Response;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

use Plack::App::File;

use HTTP::Request::Common;

my $app = Plack::App::File->new( root => 't')->to_app;
$app = Plack::Middleware::Deflater->wrap($app);

open my $f, '>', "t/deflater_test.txt" or die $!;
print $f '1234567890' x 1000;
close $f;

END { unlink('t/deflater_test.txt') }

test_tcp(
    client => sub {
        my $port = shift;

        my $ua = LWP::UserAgent->new;
        $ua->timeout(2);
        my $req = GET ("http://localhost:$port/deflater_test.txt");
        $req->header('Accept-Encoding', 'gzip');
        my $res = $ua->request($req);
        if ($res->is_success) {

            gunzip \$res->content => \(my $output)
               or die "gunzip failed: $GunzipError\n";
            is(length($output), 10000);
        }
        else {
            ok(0);
        }
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
        $server->run($app);
    },
);

done_testing();

