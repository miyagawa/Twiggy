package Plack::Server::AnyEvent::Writer;

use strict;
use warnings;

use AnyEvent::Handle;

sub new {
    my ( $class, $socket, $exit ) = @_;

    bless { handle => AnyEvent::Handle->new( fh => $socket ), exit_guard => $exit }, $class;
}

sub poll_cb {
    my ( $self, $cb ) = @_;

    my $handle = $self->{handle};

    if ( $cb ) {
        # notifies that now is a good time to ->write
        $handle->on_drain(sub {
            do {
                if ( $self->{in_poll_cb} ) {
                    $self->{poll_again}++;
                    return;
                } else {
                    local $self->{in_poll_cb} = 1;
                    $cb->($self);
                }
            } while ( delete $self->{poll_again} );
        });

        # notifies of client close
        $handle->on_error(sub {
            my $err = $_[2];
            $handle->destroy;
            $cb->(undef, $err);
        });
    } else {
        $handle->on_drain;
        $handle->on_error;
    }
}

sub write { $_[0]{handle}->push_write($_[1]) }

sub close {
    my $self = shift;

    $self->{exit_guard}->end;

    my $handle = $self->{handle};

    # kill poll_cb, but not $handle
    $handle->on_drain;
    $handle->on_error;

    $handle->on_drain(sub {
        shutdown $_[0]->fh, 1;
        $_[0]->destroy;
        undef $handle;
    });
}

sub DESTROY { $_[0]->close }

# ex: set sw=4 et:

1;
__END__
