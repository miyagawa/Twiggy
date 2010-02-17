package Twiggy::Server::Engine::Default;
use strict;

sub new { bless {@_}, shift }

sub run {
    my ($self, $server) = @_;

    my $exit = $server->{exit_guard} = AE::cv {
        # Make sure that we are not listening on a socket anymore, while
        # other events are being flushed
        delete $server->{listen_guards};
    };
    $exit->begin;

    my $w; $w = AE::signal QUIT => sub { $exit->end; undef $w };
    $exit->recv;
}

1;
