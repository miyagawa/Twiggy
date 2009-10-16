package Plack::Server::AnyEvent::Writer;

use strict;
use warnings;

use AnyEvent::Handle;

sub new {
    my ( $class, $socket ) = @_;

    bless { handle => AnyEvent::Handle->new( fh => $socket ) }, $class;
}

sub poll_cb {
    my ( $self, $cb ) = @_;

    my $handle = $self->{handle};

    if ( $cb ) {
        # notifies that now is a good time to ->write
        $handle->on_drain(sub { $cb->($self) });

        # notifies of client close
        $handle->on_error(sub {
            $handle->destroy;
            $cb->(undef, $_[2]);
        });
    } else {
        $handle->on_drain;
        $handle->on_error;
    }
}

sub write { $_[0]{handle}->push_write($_[1]) }

sub close {
    my $self = shift;

    my $handle = $self->{handle};

    # kill poll_cb, but not $handle
    $handle->on_drain;
    $handle->on_error;

    $handle->push_shutdown;
}

sub DESTROY { $_[0]->close }

# ex: set sw=4 et:

1;
__END__
