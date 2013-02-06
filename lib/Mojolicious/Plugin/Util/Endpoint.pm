package Mojolicious::Plugin::Util::Endpoint;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::URL;

our $VERSION = '0.08';

# Todo: Update to https://tools.ietf.org/html/rfc6570
# Todo: Allow for changing scheme, port, host etc. afterwards

# Endpoint hash
our %endpoints;

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  # Add 'endpoints' command
  push @{$mojo->commands->namespaces}, __PACKAGE__;

  # Add 'endpoint' shortcut
  $mojo->routes->add_shortcut(
    endpoint => sub {
      my ($route, $name, $param) = @_;

      # Endpoint already defined
      if (exists $endpoints{$name}) {
	$mojo->log->debug(qq{Route endpoint "$name" already defined});
	return $route;
      };

      # Route defined
      $route->name($name);

      # Search for placeholders
      my %placeholders;
      my $r = $route;
      $r->pattern->match('/');
      while ($r) {
	foreach (@{$r->pattern->placeholders}) {
	  $placeholders{$_} = "{$_}";
	};
	$r = $r->parent;
      };

      # Set Endpoint url
      my $endpoint_url =
	$mojo->url_for(
	  $name => %placeholders
	)->to_abs->clone;

      for my $url ($endpoint_url) {
	foreach (qw/host port scheme query/) {
	  $url->$_($param->{$_}) if exists $param->{$_};
	};
      };

      # Set to stash
      $endpoints{$name} = $endpoint_url;

      return $route;
    });

  # Add 'endpoint' helper
  $mojo->helper(
    endpoint => sub {
      my $c           = shift;
      my $name        = shift;
      my $given_param = shift || {};

      # Define endpoint by string
      unless (ref $given_param) {
	return ($endpoints{$name} = Mojo::URL->new($given_param));
      }

      # Define endpoint by Mojo::URL
      elsif (ref $given_param eq 'Mojo::URL') {
	return ($endpoints{$name} = $given_param->clone);
      };

      # Endpoint undefined
      unless (defined $endpoints{$name}) {
	$c->app->log->warn("No endpoint defined for $name");
	return $c->url_for($name)->to_abs->to_string;
      };

      # Get url for route
      my $endpoint_url = $endpoints{$name}->clone;

      # Add request information
      my $req_url = $c->req->url->to_abs;

      for ($endpoint_url) {
	$_->host($req_url->host) unless $_->host;
	unless ($_->scheme) {
	  $_->scheme($req_url->scheme || 'http') if $_->host;
	};
	$_->port($req_url->port) unless $_->port;
      };

      # Convert object to string
      my $endpoint = $endpoint_url->to_abs->to_string;

      # Unescape template variables
      $endpoint =~
	s/\%7[bB](.+?)\%7[dD]/'{' . b($1)->url_unescape . '}'/ge;

      # No placeholders in effect
      return $endpoint unless index($endpoint,'{') >= 0;

      # Get stash or defaults hash
      my $stash_param = ref($c) eq 'Mojolicious::Controller' ?
	$c->stash : ( ref $c eq 'Mojolicious' ? $c->defaults : {} );

      # Interpolate template
      pos($endpoint) = 0;
      while ($endpoint =~ /\{([^\}\?}\?]+)\??\}/g) {

	# Save search position
	# Todo: That's not exact!
	my $val = $1;
	my $p = pos($endpoint) - length($val) - 1;

	my $fill = undef;
	# Look in given param
	if (exists $given_param->{$val}) {
	  $fill = $given_param->{$val};
	}

	# Look in stash
	elsif (exists $stash_param->{$val}) {
	  $fill = $stash_param->{$val};
	};

	if (defined $fill) {
	  $fill = b($fill)->url_escape;
	  $endpoint =~ s/\{$val\??\}/$fill/;
	};

	# Reset search position
	# Todo: (not exact if it was optional)
	pos($endpoint) = $p + length($fill || '');
      };

      # Ignore optional placeholders
      if (exists $given_param->{'?'} &&
	    !defined $given_param->{'?'}) {
	for ($endpoint) {
	  s/(?<=[\&\?])[^=]+?=\{[^\?\}]+?\?\}//g;
	  s/([\?\&])\&*/$1/g;
	  s/\&$//g;
	};
      };

      # Strip empty query marker
      $endpoint =~ s/\?$//;

      return $endpoint;
    });


  # Add 'get_endpoints' helper
  $mojo->helper(
    get_endpoints => sub {
      my $c = shift;

      # Get all endpoints
      my %endpoint_hash;
      foreach (keys %endpoints) {
	$endpoint_hash{$_} = $c->endpoint($_);
      };

      # Return endpoint hash
      return \%endpoint_hash;
    });
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::Util::Endpoint - Use template URIs in Mojolicious


=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Util::Endpoint');

  # Mojolicious::Lite
  plugin 'Util::Endpoint';

  my $rs = $mojo->routes;

  # Set endpoint
  my $r = $rs->route('/:user')->endpoint(
    webfinger => {
      query  => [
        q => '{uri}'
      ]
    });

  return $self->endpoint('webfinger');
  # https://sojolicio.us/{user}?q={uri}

  $self->stash(user => 'Akron');

  return $self->endpoint('webfinger');
  # https://sojolicio.us/Akron?q={uri}

  return $self->endpoint(webfinger => {
    uri => 'acct:akron@sojolicio.us'
  });
  # https://sojolicio.us/Akron?q=acct%3Aakron%40sojolicio.us


=head1 DESCRIPTION

L<Mojolicious::Plugin::Util::Endpoint> is a plugin that
allows for the simple establishment of endpoint URIs.
This is similar to the C<url_for> method of L<Mojolicious::Controller>,
but includes support for template URIs with parameters
(as used in, e.g., Host-Meta or OpenSearch).


=head1 METHODS

=head2 register

  # Mojolicious
  $app->plugin('Util::Endpoint');

  # Mojolicious::Lite
  plugin 'Util::Endpoint';

Called when registering the plugin.


=head1 SHORTCUTS

=head2 endpoint

  my $rs = $mojo->routes
  my $r = $rs->route('/suggest')->endpoint(
    opensearch => {
      scheme => 'https',
      host   => 'sojolicio.us',
      port   => 3000,
      query  => [
        q     => '{searchTerms}',
        start => '{startIndex?}'
      ]
    });

Establishes an endpoint defined for a service.
It accepts optional parameters C<scheme>, C<host>,
a C<port> and query parameters (C<query>),
overwriting the current values of C<url_for>.
Template parameters need curly brackets, optional
template parameters need a question mark before
the closing bracket.
Optional path placeholders are currenty not supported.
This also defines a name attribute to the route for
using with C<url_for>.
Returns the route.


=head1 HELPERS

=head2 endpoint

  # In Controller:
  #   Set endpoints:
  $self->endpoint(hub => 'http://sojolicio.us/search?q={searchTerm}');
  $self->endpoint(hub => Mojo::URL->new('http://pubsubhubbub.appspot.com/'));

  #   Get endpoints:
  return $self->endpoint('webfinger');
  return $self->endpoint(webfinger => { user => 'me' } );

  # In Template:
  <%= endpoint 'webfinger' %>

Get or set endpoints defined for a specific service.

For setting it accepts the name of the endpoint and
either a string with the endpoint URI or a L<Mojo::URL> object.

For getting it accepts the name of the endpoint and
additional stash values for the route as a hash reference.
These stash values override existing stash values from
the controller and fill the template variables.

  # In Controller:
  return $self->endpoint('opensearch');
  # https://sojolicio.us/suggest?q={searchTerms}&start={startIndex?}

  return $self->endpoint(opensearch => {
    searchTerms => 'simpson',
    '?' => undef
  });
  # https://sojolicio.us/suggest?q=simpson

The special parameter C<?> can be set to C<undef> to ignore
all undefined optional template parameters.

If the defined endpoint can't be found, the value for C<url_for>
is returned.


=head2 get_endpoints

  # In Controller:
  my $hash = $self->get_endpoints;

  while (my ($key, $value) = each %$hash) {
    print $key, ' => ', $value, "\n";
  };

Returns a hash of all endpoints, interpolated with the current
controller stash.

B<Note:> This helper is EXPERIMENTAL and may be deprecated in further releases.

=head1 COMMANDS

=head2 endpoints

  $ perl app.pl endpoints

Show all endpoints of the app established by this plugin.


=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support).


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Util-Endpoint


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
