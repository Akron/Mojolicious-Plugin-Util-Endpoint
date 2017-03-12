#!/usr/bin/env perl
use strict;
use warnings;

BEGIN {
  our @INC;
  unshift(@INC, '../../lib', '../lib');
};

use Test::More;
use Test::Mojo;
use Test::Output;

use Mojolicious::Lite;
use Mojo::ByteStream 'b';

my $t = Test::Mojo->new;
my $app = $t->app;

$app->plugin('Util::Endpoint');

my ($level, $msg);
$app->log->on(
  message => sub {
    (my $l2, $level, $msg) = @_;
  });

my $endpoint_host = 'endpoi.nt';

# Set endpoint
my $r_test = $app->routes->route('/test');
$r_test->endpoint(
  'test1' =>
    {
      host   => $endpoint_host,
      scheme => 'https'
    });

$app->routes->get('/test2')->to(
  cb => sub {
    my $c = shift;
    return $c->render(text => $c->endpoint('test1'))
  });

$t->get_ok('/test2')->content_is('https://endpoi.nt/test');

done_testing;
