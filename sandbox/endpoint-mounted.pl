#!/usr/bin/env perl
use Mojolicious::Lite;

use lib '../lib';

plugin 'Util::Endpoint';

get '/test' => sub {
  shift->render_text('Mounted.');
};

(get '/probe')->to(cb => sub { shift->render_text('Mounted Endpoint.')})->endpoint('probe')->name('probe2');

get '/get-ep' => sub {
  my $c = shift;
  return $c->render_text($c->endpoint('probe'));
};

get '/get-url' => sub {
  my $c = shift;
  return $c->render_text($c->url_for('probe2'));
};

app->start;
