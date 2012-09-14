#!perl -Tw

# Doesn't test anything useful yet

use strict;
use warnings;
use Test::More tests => 5;
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

		skip 'CHI not installed', 3 if $@;

		diag("Using CHI $CHI::VERSION");

		my $cache = CHI->new(driver => 'Memory', datastore => {});

		CGI::Buffer::set_options(cache => $cache, cache_key => 'xyzzy');
		ok(!CGI::Buffer::is_cached());

		$cache->set('xyzzy/body', 'foo');
		ok(CGI::Buffer::is_cached());

		$cache->set('xyzzy/headers', 'bar');
		ok(CGI::Buffer::is_cached());
	}
}
