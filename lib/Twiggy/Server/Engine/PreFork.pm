package Twiggy::Server::Engine::PreFork;
use strict;
use Parallel::Prefork;

sub new { bless {@_}, shift }

sub run {
    my ($self, $server) = @_;

    $server->{max_requests} ||= 1000;
    my $pm = Parallel::Prefork->new({
        max_workers => $server->{workers},
        trap_signals => {
            TERM => 'TERM',
            HUP  => 'TERM',
        },
    });
    while ($pm->signal_received ne 'TERM') {
        $pm->start and next;
        Twiggy::Server::DEBUG && warn "[$$] start";
        my $exit = $server->{exit_guard} = AE::cv;
        $exit->begin;
        my $w; $w = AE::signal TERM => sub { $exit->end; undef $w };
        $exit->recv;
        Twiggy::Server::DEBUG && warn "[$$] finish";
        $pm->finish;
    }
    $pm->wait_all_children;
}

1;
