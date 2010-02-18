package Plack::Handler::Twiggy;
use strict;

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub run {
    my ($self, $app) = @_;

    my $class = $ENV{SERVER_STARTER_PORT} ?
        'Twiggy::Server::SS' : 'Twiggy::Server';
    eval "require $class";
    die if $@;

    $class->new(%{$self})->run($app);
}
    

1;

__END__

=head1 NAME

Plack::Handler::Twiggy - Adapter for Twiggy

=head1 SYNOPSIS

  plackup -s Twiggy --port 9090

  # with start_server
  start_server --port=9090 plackup -s Twiggy 

=head1 DESCRIPTION

This is an adapter to run PSGI apps on Twiggy via L<plackup>.

=head1 SEE ALSO

L<plackup>

=cut

