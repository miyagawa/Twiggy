requires 'AnyEvent';
requires 'HTTP::Status';
requires 'Plack', '0.99';
requires 'Try::Tiny';
requires 'perl', '5.008001';

on test => sub {
    requires 'Test::More';
    requires 'Test::Requires';
    requires 'Test::TCP';
};
