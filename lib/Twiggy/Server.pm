package Twiggy::Server;
use strict;
use warnings;

use Scalar::Util qw(blessed weaken);
use Try::Tiny;
use Carp;

use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Errno qw(EAGAIN EINTR);
use IO::Handle;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::Util qw(WSAEWOULDBLOCK);

use HTTP::Status;
use Plack::HTTPParser qw(parse_http_request);
use Plack::Util;

use constant DEBUG => $ENV{TWIGGY_DEBUG};
use constant HAS_AIO => !$ENV{PLACK_NO_SENDFILE} && try {
    require AnyEvent::AIO;
    require IO::AIO;
    1;
};

open my $null_io, '<', \'';

sub new {
    my($class, @args) = @_;

    return bless {
        no_delay => 1,
        timeout => 300,
        read_chunk_size => 4096,
        @args,
    }, $class;
}

sub register_service {
    my($self, $app) = @_;

    my @listen = @{$self->{listen} || [ ($self->{host} || '') . ":$self->{port}" ]};
    for my $listen (@listen) {
        push @{$self->{listen_guards}}, $self->_create_tcp_server($listen, $app);
    }

    $self->{exit_guard} = AE::cv {
        # Make sure that we are not listening on a socket anymore, while
        # other events are being flushed
        delete $self->{listen_guards};
    };
    $self->{exit_guard}->begin;
}

sub _create_tcp_server {
    my ( $self, $listen, $app ) = @_;

    my($host, $port, $is_tcp);
    if ($listen =~ /:\d+$/) {
        ($host, $port) = split /:/, $listen;
        $host = undef if $host eq '';
        $is_tcp = 1;
    } else {
        $host = "unix/";
        $port = $listen;
    }

    return tcp_server $host, $port, $self->_accept_handler($app, $is_tcp), 
        $self->_accept_prepare_handler;
}

sub _accept_prepare_handler {
    my $self = shift;
    return sub {
        my ( $fh, $host, $port ) = @_;
        DEBUG && warn "Listening on $host:$port\n";
        $self->{prepared_host} = $host;
        $self->{prepared_port} = $port;
        $self->{server_ready}->({
            host => $host,
            port => $port,
            server_software => 'Twiggy',
        }) if $self->{server_ready};

        return $self->{backlog} || 0;
    };
}

sub _accept_handler {
    my ( $self, $app, $is_tcp ) = @_;

    return sub {
        my ( $sock, $peer_host, $peer_port ) = @_;

        DEBUG && warn "$sock Accepted connection from $peer_host:$peer_port\n";
        return unless $sock;
        $self->{exit_guard}->begin;

        if ( $is_tcp && $self->{no_delay} ) {
            setsockopt($sock, IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
        }

        my $headers = "";
        my $try_parse = sub {
            if ( $self->_try_read_headers($sock, $headers) ) {
                my $env = {
                    SERVER_PORT         => $self->{prepared_port},
                    SERVER_NAME         => $self->{prepared_host},
                    SCRIPT_NAME         => '',
                    REMOTE_ADDR         => $peer_host,
                    'psgi.version'      => [ 1, 0 ],
                    'psgi.errors'       => *STDERR,
                    'psgi.url_scheme'   => 'http',
                    'psgi.nonblocking'  => Plack::Util::TRUE,
                    'psgi.streaming'    => Plack::Util::TRUE,
                    'psgi.run_once'     => Plack::Util::FALSE,
                    'psgi.multithread'  => Plack::Util::FALSE,
                    'psgi.multiprocess' => Plack::Util::FALSE,
                    'psgi.input'        => undef, # will be set by _run_app()
                    'psgix.io'          => $sock,
                    'psgix.input.buffered' => Plack::Util::TRUE,
                };

                my $reqlen = parse_http_request($headers, $env);
                DEBUG && warn "$sock Parsed HTTP headers: request length=$reqlen\n";

                if ( $reqlen < 0 ) {
                    die "bad request";
                } else {
                    return $env;
                }
            }

            return;
        };

        local $@;
        unless ( eval {
            if ( my $env = $try_parse->() ) {
                # the request data is already available, no need to parse more
                $self->_run_app($app, $env, $sock);
            } else {
                # there's not yet enough data to parse the request,
                # set up a watcher
                $self->_create_req_parsing_watcher( $sock, $try_parse, $app );
            };

            1;
        }) {
            $self->_bad_request($sock);
        }
    };
}

# returns a closure that tries to parse
# this is not a method because it needs a buffer per socket
sub _try_read_headers {
    my ( $self, $sock, undef ) = @_;

    # FIXME add a timer to manage read timeouts
    local $/ = "\012";

    read_more: for my $headers ( $_[2] ) {
        if ( defined(my $line = <$sock>) ) {
            $headers .= $line;

            if ( $line eq "\015\012" or $line eq "\012" ) {
                # got an empty line, we're done reading the headers
                return 1;
            } else {
                # try to read more lines using buffered IO
                redo read_more;
            }
        } elsif ($! and $! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK ) {
            die $!;
        } elsif (!$!) {
            die "client disconnected";
        }
    }

    DEBUG && warn "$sock did not read to end of req, wait for more data to arrive\n";
    return;
}

sub _create_req_parsing_watcher {
    my ( $self, $sock, $try_parse, $app ) = @_;

    my $headers_io_watcher;

    my $timeout_timer = AE::timer $self->{timeout}, 0, sub {
        DEBUG && warn "$sock Timeout\n";
        undef $headers_io_watcher;
        undef $try_parse;
        undef $sock;
    } if $self->{timeout};

    $headers_io_watcher = AE::io $sock, 0, sub {
        try {
            if ( my $env = $try_parse->() ) {
                undef $headers_io_watcher;
                undef $timeout_timer;
                $self->_run_app($app, $env, $sock);
            }
        } catch {
            undef $headers_io_watcher;
            undef $timeout_timer;
            $self->_bad_request($sock);
        }
    };
}

sub _bad_request {
    my ( $self, $sock ) = @_;

    return unless defined $sock and defined fileno $sock;

    $self->_write_psgi_response(
        $sock,
        [
            400,
            [ 'Content-Type' => 'text/plain' ],
            [ ],
        ],
    );

    return;
}

sub _read_chunk {
    my ($self, $sock, $remaining, $cb) = @_;

    my $data = '';
    my $read_chunk_size = $self->{read_chunk_size};

    my $try_read = sub {
        READ_MORE: {
            my $read_size = $remaining > $read_chunk_size ? $read_chunk_size : $remaining;
            my $rlen = read($sock, $data, $read_size, length($data));

            if (defined $rlen and $rlen > 0) {
                $remaining -= $rlen;

                if ($remaining <= 0) {
                    $cb->($data);
                    return 1;
                } else {
                    redo READ_MORE;
                }
            } elsif (defined $rlen) {
                $cb->($data);
                return 1;
            } elsif ($! and $! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
                die $!;
            }
        }

        return;
    };

    unless ($try_read->()) {
        my $rw; $rw = AE::io($sock, 0, sub {
            try {
                if ($try_read->()) {
                    undef $rw;
                }
            } catch {
                undef $rw;
                $self->_bad_request($sock);
            };
        });
    }
}

sub _run_app {
    my($self, $app, $env, $sock) = @_;

    unless ($env->{'psgi.input'}) {
        if ($env->{CONTENT_LENGTH} && $env->{REQUEST_METHOD} =~ /^(?:POST|PUT)$/) {
            $self->_read_chunk($sock, $env->{CONTENT_LENGTH}, sub {
                my ($data) = @_;
                open my $input, '<', \$data;
                $env->{'psgi.input'} = $input;
                $self->_run_app($app, $env, $sock);
            });
            return;
        } else {
            $env->{'psgi.input'} = $null_io;
        }
    }

    my $res = Plack::Util::run_app $app, $env;

    if ( ref $res eq 'ARRAY' ) {
        $self->_write_psgi_response($sock, $res);
    } elsif ( blessed($res) and $res->isa("AnyEvent::CondVar") ) {
        $res->cb(sub { $self->_write_psgi_response($sock, shift->recv) });
    } elsif ( ref $res eq 'CODE' ) {
        $res->(
            sub {
                my $res = shift;

                if ( @$res < 2 ) {
                    croak "Insufficient arguments";
                } elsif ( @$res == 2 ) {
                    my ( $status, $headers ) = @$res;

                    $self->_flush($sock);

                    my $writer = Twiggy::Writer->new($sock, $self->{exit_guard});

                    my $buf = $self->_format_headers($status, $headers);
                    $writer->write($$buf);

                    return $writer;
                } else {
                    my ( $status, $headers, $body, $post ) = @$res;
                    my $cv = $self->_write_psgi_response($sock, [ $status, $headers, $body ]);
                    $cv->cb(sub { $post->() }) if $post;
                }
            },
            $sock,
        );
    } else {
        croak("Unknown response type: $res");
    }
}

sub _write_psgi_response {
    my ( $self, $sock, $res ) = @_;

    if ( ref $res eq 'ARRAY' ) {
        if ( scalar @$res == 0 ) {
            # no response
            $self->{exit_guard}->end;
            return;
        }

        my ( $status, $headers, $body ) = @$res;

        my $cv = AE::cv;

        $self->_write_headers( $sock, $status, $headers )->cb(sub {
            local $@;
            if ( eval { $_[0]->recv; 1 } ) {
                $self->_write_body($sock, $body)->cb(sub {
                    shutdown $sock, 1;
                    $self->{exit_guard}->end;
                    local $@;
                    eval { $cv->send($_[0]->recv); 1 } or $cv->croak($@);
                });
            }
        });

        return $cv;
    } else {
        no warnings 'uninitialized';
        warn "Unknown response type: $res";
        return $self->_write_psgi_response($sock, [ 204, [], [] ]);
    }
}

sub _write_headers {
    my ( $self, $sock, $status, $headers ) = @_;

    $self->_write_buf( $sock, $self->_format_headers($status, $headers) );
}

sub _format_headers {
    my ( $self, $status, $headers ) = @_;

    my $hdr = sprintf "HTTP/1.0 %d %s\015\012", $status, HTTP::Status::status_message($status);

    my $i = 0;

    my @delim = ("\015\012", ": ");

    foreach my $str ( @$headers ) {
        $hdr .= $str . $delim[++$i % 2];
    }

    $hdr .= "\015\012";

    return \$hdr;
}

# this flushes just the output buffer, not the input buffer (unlike
# $handle->flush)
sub _flush {
	my ( $self, $sock ) = @_;

    local $| = 1;
    print $sock '';
}

# helper routine, similar to push write, but respects buffering, and refcounts
# itself
sub _write_buf {
    my($self, $socket, $data) = @_;

    no warnings 'uninitialized';

    # try writing immediately
    if ( (my $written = syswrite($socket, $$data)) < length($$data) ) {
        my $done = defined(wantarray) && AE::cv;

        # either the write failed or was incomplete

        if ( !defined($written) and $! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
            # a real write error occured, like EPIPE
            $done->croak($!) if $done;
            return $done;
        }

        # the write was either incomplete or a non fatal error occured, so we
        # need to set up an IO watcher to wait until we can properly write

        my $length = length($$data);

        my $write_watcher;
        $write_watcher = AE::io $socket, 1, sub {
            write_more: {
                my $out = syswrite($socket, $$data, $length - $written, $written);

                if ( defined($out) ) {
                    $written += $out;

                    if ( $written == $length ) {
                        undef $write_watcher;
                        $done->send(1) if $done;
                    } else {
                        redo write_more;
                    }
                } elsif ($! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
                    $done->croak($!) if $done;
                    undef $write_watcher;
                }
            }
        };

        return $done;
    } elsif ( defined wantarray ) {
        my $done = AE::cv;
        $done->send(1);
        return $done;
    }
}

sub _write_body {
    my ( $self, $sock, $body ) = @_;

    if ( ref $body eq 'ARRAY' ) {
        my $buf = join "", @$body;
        return $self->_write_buf($sock, \$buf);
    } elsif ( Plack::Util::is_real_fh($body) ) {
        # real handles use nonblocking IO
        # either AIO or using watchers, with sendfile or with copying IO
        return $self->_write_real_fh($sock, $body);
    } elsif ( blessed($body) and $body->can("string_ref") ) {
        # optimize IO::String to not use its incredibly slow getline
        if ( my $pos = $body->tell ) {
            my $str = substr ${ $body->string_ref }, $pos;
            return $self->_write_buf($sock, \$str);
        } else {
            return $self->_write_buf($sock, $body->string_ref);
        }
    } else {
        return $self->_write_fh($sock, $body);
    }
}

# like Plack::Util::foreach, but nonblocking on the output
# handle
sub _write_fh {
    my ( $self, $sock, $body ) = @_;

    my $handle = AnyEvent::Handle->new( fh => $sock );
    my $ret = AE::cv;

    $handle->on_error(sub {
        my $err = $_[2];
        $handle->destroy;
        $ret->send($err);
    });

    no warnings 'recursion';
    $handle->on_drain(sub {
        local $/ = \ $self->{read_chunk_size};
        if ( defined( my $buf = $body->getline ) ) {
            $handle->push_write($buf);
        } elsif ( $! ) {
            $ret->croak($!);
            $handle->destroy;
        } else {
            $body->close;
            $handle->on_drain(sub {
                shutdown $handle->fh, 1;
                $handle->destroy;
                $ret->send(1);
            });
        }
    });

    return $ret;
}

# when the body handle is a real filehandle we use this routine, which is more
# careful not to block when reading the response too

# FIXME support only reading $length bytes from $body, instead of until EOF
# FIXME use len = 0 param to sendfile
# FIXME use Sys::Sendfile in nonblocking mode if AIO is not available
# FIXME test sendfile on non file backed handles
sub _write_real_fh {
    my ( $self, $sock, $body ) = @_;

    if ( HAS_AIO and -s $body ) {
        my $cv = AE::cv;
        my $offset = 0;
        my $length = -s $body;
        $sock->blocking(1);
        my $sendfile; $sendfile = sub {
            IO::AIO::aio_sendfile( $sock, $body, $offset, $length - $offset, sub {
                my $ret = shift;
                $offset += $ret if $ret > 0;
                if ($offset >= $length || ($ret == -1 && ! ($! == EAGAIN || $! == EINTR))) {
                    if ( $ret == -1 ) {
                        $cv->croak($!);
                    } else {
                        $cv->send(1);
                    }

                    undef $sendfile;
                    undef $sock;
                } else {
                    $sendfile->();
                }
            });
        };
        $sendfile->();
        return $cv;
    } else {
        return $self->_write_fh($sock, $body);
    }
}

sub run {
    my $self = shift;
    $self->register_service(@_);

    my $w; $w = AE::signal QUIT => sub { $self->{exit_guard}->end; undef $w };
    $self->{exit_guard}->recv;
}

package Twiggy::Writer;
use AnyEvent::Handle;

sub new {
    my ( $class, $socket, $exit ) = @_;

    bless { handle => AnyEvent::Handle->new( fh => $socket ), exit_guard => $exit }, $class;
}

sub write { $_[0]{handle}->push_write($_[1]) }

sub close {
    my $self = shift;

    my $exit_guard = delete $self->{exit_guard};
    $exit_guard->end if $exit_guard;

    my $handle = delete $self->{handle};
    if ($handle) {
        $handle->on_drain;
        $handle->on_error;

        $handle->on_drain(sub {
            shutdown $_[0]->fh, 1;
            $_[0]->destroy;
            undef $handle;
        });
    }
}

sub DESTROY { $_[0]->close }

package Twiggy::Server;

1;
__END__
