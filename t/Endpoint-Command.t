#!/usr/bin/env perl
use strict;
use warnings;

BEGIN {
  our @INC;
  unshift(@INC, '../../lib', '../lib', 'lib');
};

use Test::More;
use Test::Mojo;
use Test::Output;

use Mojolicious::Lite;
use Mojo::ByteStream 'b';

my $t = Test::Mojo->new;
my $app = $t->app;

use_ok('Mojolicious::Plugin::Util::Endpoint::endpoints');

$app->plugin('Util::Endpoint');

get('/probe1')->to(
  cb => sub {
    my $c = shift;
  })->endpoint('probe1');

get('/probe1/probe2')->to(
  cb => sub {
    my $c = shift;
  })->endpoint(
    probe2 => {
      query => [
        q     => '{searchTerms}',
        start => '{startIndex?}'
      ]
    }
  );


my $ep = Mojolicious::Plugin::Util::Endpoint::endpoints->new;
$ep->app($app);

stdout_is(
  sub { $ep->run },
qq{ "probe1"             /probe1
 "probe2"             /probe1/probe2?q={searchTerms}&start={startIndex?}\n\n},
  'Test output'
);

done_testing;
