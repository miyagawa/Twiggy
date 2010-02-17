package Twiggy::Server::PreFork;
use strict;
use Parallel::Prefork;

sub _accept_handler {
    my $self = shift;

    my $cb = $self->SUPER::_accept_handler(@_);
    return sub {
        $self->{reqs_per_child}++;
        eval {
            $cb->(@_);
        };
        my $e = $@;

        if ($self->{reqs_per_child} > $self->{max_requests}) {
            Twiggy::Server::DEBUG && warn "[$$] max requests ( $self->{max_requests}) reached";
            my $cv = $self->{exit_guard};
            $cv->end;
        }
    };
}

sub run {
    my $self = shift;
    $self->register_service(@_);

    $self->{max_requests} ||= 1000;
    my $pm = Parallel::Prefork->new({
        max_workers => $self->{workers},
        trap_signals => {
            TERM => 'TERM',
            HUP  => 'TERM',
        },
    });
    while ($pm->signal_received ne 'TERM') {
        $pm->start and next;
        Twiggy::Server::DEBUG && warn "[$$] start";
        my $exit = $self->{exit_guard} = AE::cv;
        $exit->begin;
        my $w; $w = AE::signal TERM => sub { $exit->end; undef $w };
        $exit->recv;
        Twiggy::Server::DEBUG && warn "[$$] finish";
        $pm->finish;
    }
    $pm->wait_all_children;
}

1;