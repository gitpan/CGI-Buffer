#!perl -Tw

# Doesn't test anything useful yet

use strict;
use warnings;
use Test::More tests => 3;
# use Test::NoWarnings;	# HTML::Clean has them

BEGIN {
	use_ok('CGI::Buffer');
}

CACHED: {
	delete $ENV{'REMOTE_ADDR'};
	delete $ENV{'HTTP_USER_AGENT'};

	ok(CGI::Buffer::is_cached() == 0);

	SKIP: {
		eval {
			require CHI;

			CHI->import;
		};

		skip 'CHI not installed', 1 if $@;

		diag("Using CHI $CHI::VERSION");

		my $hash = {};
		my $cache = CHI->new(driver => 'Memory', datastore => $hash);

		CGI::Buffer::set_options(cache => $cache, cache_key => 'xyzzy');

		ok(!CGI::Buffer::is_cached());
	}
}
