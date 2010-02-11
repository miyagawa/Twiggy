#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

use Pod::Usage;

use AnyEvent::Socket;
use AnyEvent::Handle;
use Text::MicroTemplate::File;
use Path::Class qw/file dir/;
use JSON;
use Plack::Request;
use Plack::Builder;

my $mtf = Text::MicroTemplate::File->new(
    include_path => ["templates"],
);

my(@clients, %room);

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    if ($req->path eq '/') {
        $res->content_type('text/html; charset=utf-8');
        $res->content($mtf->render_file('index.mt'));
    } elsif ($req->path =~ m!^/chat!) {
        my $room = ($req->path =~ m!^/chat/(.+)!)[0];
        my $host = $req->header('Host');
        $res->content_type('text/html;charset=utf-8');
        $res->content($mtf->render_file('room.mt', $host, $room));
    } elsif ($req->path =~ m!^/ws!) {
        my $room = ($req->path =~ m!^/ws/(.+)!)[0];

        unless (    $env->{HTTP_CONNECTION} eq 'Upgrade'
                and $env->{HTTP_UPGRADE} eq 'WebSocket') {
            $res->code(400);
            return $res->finalize;
        }

        return sub {
            my $respond = shift;

            # XXX: we could use $respond to send handshake response
            # headers, but 101 status message should be 'Web Socket
            # Protocol Handshake' rather than 'Switching Protocols'
            # and we should send HTTP/1.1 response which Twiggy
            # doesn't implement yet.

            my $hs = join "\015\012",
                "HTTP/1.1 101 Web Socket Protocol Handshake",
                "Upgrade: WebSocket",
                "Connection: Upgrade",
                "WebSocket-Origin: $env->{HTTP_ORIGIN}",
                "WebSocket-Location: ws://$env->{HTTP_HOST}$env->{SCRIPT_NAME}$env->{PATH_INFO}",
                '', '';

            my $fh = $env->{'psgix.io'} or die "This server does not support psgix.io extension";
            my $h = AnyEvent::Handle->new( fh => $fh );
            $h->on_error(sub {
                warn 'err: ', $_[2];
                delete $room{ $room }[fileno($fh)] if $room;
                undef $h;
            });

            $h->push_write($hs);

            # connection ready
            $room{ $room }[ fileno($fh) ] = $h;

            $h->on_read(sub {
                shift->push_read( line => "\xff", sub {
                    my ($h, $json) = @_;
                    $json =~ s/^\0//;

                    my $data = JSON::decode_json($json);
                    $data->{address} = $req->address;
                    $data->{time} = time;

                    my $msg = JSON::encode_json($data);

                    # broadcast
                    for my $c (grep { defined } @{ $room{$room} || [] }) {
                        $c->push_write("\x00" . $msg . "\xff");
                    }
                });
            });
        };
    } else {
        $res->code(404);
    }

    $res->finalize;
};

builder {
    enable "Static", path => sub { s!^/static/!! }, root => 'static';
    $app;
};
