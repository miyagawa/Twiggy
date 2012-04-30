package Twiggy::Server::SS;
use strict;
use warnings;
use base qw(Twiggy::Server);
use AnyEvent;
use AnyEvent::Util qw(fh_nonblocking guard);
use AnyEvent::Socket qw(format_address);
use Server::Starter qw(server_ports);

sub start_listen {
    my ($self, $app) = @_;

    if (Twiggy::Server::DEBUG() && $self->{listen}) {
        warn "'listen' option is currently ignored when used in conjunction with Server::Starter (start_server script)";
    }

    my $host = $self->{host} || '';

    my @listen;
    my $ports = server_ports();
    while (my ($listen, $fd) = each %$ports ) {
        push @listen, $listen;
        $self->_create_ss_tcp_server($listen, $fd, $app);
    }

    # overwrite, just in case somebody wants to refer to it afterwards
    $self->{listen} = \@listen;
}

sub _create_ss_tcp_server {
    my ($self, $listen, $fd, $app) = @_;

    my($host, $port, $is_tcp);
    if ($listen =~ /:\d+$/) {
        ($host, $port) = split /:/, $listen;
        $host = undef if $host eq '';
        $port = undef if $port == 0;
        $is_tcp = 1;
    } else {
        $host = "unix/";
        $port = $listen;
    }

    # /WE/ don't care what the address family, type of socket we got, just
    # create a new handle, and perform a fdopen on it. So that part of
    # AE::Socket::tcp_server is stripped out

    my %state;
    $state{fh} = IO::Socket::INET->new(
        Proto => 'tcp',
        Listen => 128, 
    );

    $state{fh}->fdopen( $fd, 'w' ) or
        Carp::croak "failed to bind to listening socket: $!";
    fh_nonblocking $state{fh}, 1;

    my($listen_host, $listen_port);

    my $len;
    my $prepare = $self->_accept_prepare_handler(\$listen_host, \$listen_port);
    if ($prepare) {
        my ($service, $host) = AnyEvent::Socket::unpack_sockaddr getsockname $state{fh};
        $len = $prepare && $prepare->( $state{fh}, format_address $host, $service );
    }

    $len ||= 128;

    listen $state{fh}, $len or Carp::croak "listen: $!";

    my $accept = $self->_accept_handler($app, $is_tcp, \$listen_host, \$listen_port);
    $state{aw} = AE::io $state{fh}, 0, sub {
        # this closure keeps $state alive
        while ($state{fh} && (my $peer = accept my $fh, $state{fh})) {
            fh_nonblocking $fh, 1; # POSIX requires inheritance, the outside world does not

            my ($service, $host) = AnyEvent::Socket::unpack_sockaddr($peer);
            $accept->($fh, format_address $host, $service);
        }
    };

    defined wantarray
        ? guard { %state = () } # clear fh and watcher, which breaks the circular dependency
        : ()
}

1;
