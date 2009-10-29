package Plack::Server::AnyEvent;
use strict;
use warnings;
use 5.008_001;
our $VERSION = '0.02';

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

use Plack::Middleware::ContentLength;
use Plack::Middleware::Chunked;

use constant HAS_AIO => !$ENV{PLACK_NO_SENDFILE} && try {
    require AnyEvent::AIO;
    require IO::AIO;
    1;
};

use Plack::Server::AnyEvent::Writer;

sub new {
    my($class, @args) = @_;

    return bless {
        host => undef,
        port => undef,
        no_delay => 1,
        @args,
    }, $class;
}

sub register_service {
    my($self, $app) = @_;

    $app = Plack::Middleware::ContentLength->wrap($app);
#    $app = Plack::Middleware::Chunked->wrap($app);

    $self->{listen_guard} = $self->_create_tcp_server($app);
}

sub _create_tcp_server {
    my ( $self, $app ) = @_;

    return tcp_server $self->{host}, $self->{port}, sub {
        $self->_handle_request($app, @_);
    }, sub {
        my ( $fh, $host, $port ) = @_;
        $self->{prepared_host} = $host;
        $self->{prepared_port} = $port;
        warn "Accepting requests at http://$host:$port/\n";
        return 0;
    };
}

sub _handle_request {
    my ( $self, $app, $sock, $peer_host, $peer_port ) = @_;

    return unless $sock;

    if ( $self->{no_delay} ) {
        setsockopt($sock, IPPROTO_TCP, TCP_NODELAY, 1)
            or die "setsockopt(TCP_NODELAY) failed:$!";
    }

    my $try_read = $self->_create_header_reader($sock);

    my $try_parse = sub {
        if ( my $headers = $try_read->() ) {
            my $env = {
                SERVER_PORT         => $self->{prepared_port},
                SERVER_NAME         => $self->{prepared_host},
                SCRIPT_NAME         => '',
                'psgi.version'      => [ 1, 0 ],
                'psgi.errors'       => *STDERR,
                'psgi.url_scheme'   => 'http',
                'psgi.nonblocking'  => Plack::Util::TRUE,
                'psgi.run_once'     => Plack::Util::FALSE,
                'psgi.multithread'  => Plack::Util::FALSE,
                'psgi.multiprocess' => Plack::Util::FALSE,
                'psgi.streaming'    => Plack::Util::TRUE,
                'psgi.input'        => $sock,
                'REMOTE_ADDR'       => $peer_host,
            };

            my $reqlen = parse_http_request($$headers, $env);

            if ( $reqlen < 0 ) {
                die "bad request";
            } else {
                return $env;
            }
        }

        return;
    };

    try {
        if ( my $env = $try_parse->() ) {
            # the request data is already available, no need to parse more
            $self->_run_app($app, $env, $sock);
        } else {
            # there's not yet enough data to parse the request,
            # set up a watcher
            $self->_create_req_parsing_watcher( $sock, $try_parse, $app );
        }
    } catch {
        $self->_bad_request($sock);
    };
}

# returns a closure that tries to parse
# this is not a method because it needs a buffer per socket
sub _create_header_reader {
    my ( $self, $sock ) = @_;

    my $headers = '';

    # FIXME add a timer to manage read timeouts

    return sub {
        local $/ = "\012";

        read_more: {
            if ( defined(my $line = <$sock>) ) {
                $headers .= $line;

                if ( $line eq "\015\012" or $line eq "\012" ) {
                    # got an empty line, we're done reading the headers
                    return \$headers;
                } else {
                    # try to read more lines using buffered IO
                    redo read_more;
                }
            } elsif ($! and $! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK ) {
                die $!;
            }
        }

        # did not read to end of req, wait for more data to arrive
        return;
    };
}

sub _create_req_parsing_watcher {
    my ( $self, $sock, $try_parse, $app ) = @_;

    my $headers_io_watcher;
    $headers_io_watcher = AE::io $sock, 0, sub {
        try {
            if ( my $env = $try_parse->() ) {
                undef $headers_io_watcher;
                $self->_run_app($app, $env, $sock);
            }
        } catch {
            undef $headers_io_watcher;
            $self->_bad_request($sock);
        }
    };
}

sub _bad_request {
    my ( $self, $sock ) = @_;

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

sub _run_app {
    my($self, $app, $env, $sock) = @_;

    my $res = Plack::Util::run_app $app, $env;

    if ( blessed($res) and $res->isa("AnyEvent::CondVar") ) {
        $res->cb(sub { $self->_write_psgi_response($sock, shift->recv) });
    } elsif ( ref $res eq 'CODE' ) {
        $res->(
            sub {
                my $res = shift;

                if ( @$res < 2 ) {
                    croak "Insufficient arguments";
                } elsif ( @$res == 2 ) {
                    my ( $status, $headers ) = @$res;

                    my $writer = Plack::Server::AnyEvent::Writer->new($sock);

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
        $self->_write_psgi_response($sock, $res);
    }
}

sub _write_psgi_response {
    my ( $self, $sock, $res ) = @_;

    if ( ref $res eq 'ARRAY' ) {
        return if scalar(@$res) == 0; # no response

        my ( $status, $headers, $body ) = @$res;

        my $cv = AE::cv;

        $self->_write_headers( $sock, $status, $headers )->cb(sub {
            try { shift->recv } catch { $cv->croak($_) };
            $self->_write_body($sock, $body)->cb(sub {
                try { shift->recv } catch { $cv->croak($_) };
                $cv->send(1);
            });
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

# helper routine, similar to push write, but respects buffering, and refcounts
# itself
sub _write_buf {
    my($self, $socket, $data) = @_;

    my $done = AE::cv;

    Carp::cluck($data) unless ref $data;

    my $length = length($$data);

    # flush the output buffer, but not the input buffer
    {
        local $| = 1;
        $socket->print('');
    }

    # try writing immediately
    my $written = syswrite($socket, $$data, $length) || 0;

    if ( $written < $length ) {
        # either the write failed or was incomplete, both cases are handled in
        # the watcher

        my $write_watcher;
        $write_watcher = AE::io $socket, 1, sub {
            write_more: {
                my $out = syswrite($socket, $$data, $length - $written, $written);

                if ( defined($out) ) {
                    $written += $out;

                    if ( $written == $length ) {
                        undef $write_watcher;
                        $done->send(1);
                    } else {
                        redo write_more;
                    }
                } elsif ($! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
                    undef $write_watcher;
                    $done->croak($!);
                }
            }
        };
    } else {
        $done->send(1);
    }

    return $done;
}

sub _write_body {
    my ( $self, $sock, $body ) = @_;

    if ( Plack::Util::is_real_fh($body) ) {
        # real handles use nonblocking IO
        # either AIO or using watchers, with sendfile or with copying IO
        $self->_write_real_fh($sock, $body);

    } elsif ( blessed($body) and $body->can("string_ref") ) {
        # optimize IO::String to not use its incredibly slow getline
        if ( my $pos = $body->tell ) {
            my $str = substr ${ $body->string_ref }, $pos;
            return $self->_write_buf($sock, \$str);
        } else {
            return $self->_write_buf($sock, $body->string_ref);
        }
    } else {
        # like Plack::Util::foreach, but nonblocking on the output
        # handle

        if ( ref $body eq 'ARRAY' ) {
            my $buf = join "", @$body;
            my $done = AE::cv;
            $self->_write_buf($sock, \$buf)->cb(sub {
                shutdown $sock, 1;
                $done->send(1);
            });
            return $done;
        } else {
            # flush the output buffer, but not the input buffer
            {
                local $| = 1;
                $sock->print('');
            }

            my $handle = AnyEvent::Handle->new( fh => $sock );

            my $ret = AE::cv;

            $handle->on_error(sub {
                $handle->destroy;
                $ret->send($_[2]);
            });

            $handle->on_drain(sub {
                local $/ = \4096;
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
    }
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
        # $body is a real filehandle, so set up a watcher for it
        # this is basically sendfile in userspace
        my $sock_handle = AnyEvent::Handle->new( fh => $sock );
        my $body_handle = AnyEvent::Handle->new( fh => $body );

        my $cv = AE::cv;

        my $err = sub {
            $cv->croak($_[2]);

            for ( $sock_handle, $body_handle ) {
                $_->destroy;
            }
        };

        $sock_handle->on_error($err);
        $body_handle->on_error($err);

        $body_handle->on_eof(sub {
            $body_handle->destroy;
            $sock_handle->on_drain(sub {
                shutdown $sock_handle->fh, 1;
                $sock_handle->destroy;
                $cv->send(1);
            });
        });

        $sock_handle->on_drain(sub {
            $body_handle->push_read(sub {
                $sock_handle->push_write($_[0]{rbuf});
                $_[0]{rbuf} = '';
            });
        });

        return $cv;
    }
}

sub run {
    my $self = shift;
    $self->register_service(@_);
    AnyEvent->condvar->recv;
}

# ex: set sw=4 et:

1;
__END__

=head1 NAME

Plack::Server::AnyEvent - AnyEvent based HTTP server

=head1 SYNOPSIS

  my $server = Plack::Server::AnyEvent->new(
      host => $host,
      port => $port,
  );
  $server->run($app);

=head1 DESCRIPTION

Plack::Server::AnyEvent is a Plack server implementation using
AnyEvent. This server runs in a non-blocking event loop and suitable
for event-driven web applications like streaming API servers.

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=head1 AUTHOR

Tokuhiro Matsuno

Yuval Kogman

Tatsuhiko Miyagawa

=cut
