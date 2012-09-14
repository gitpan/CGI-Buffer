#!perl -wT

use strict;
use warnings;
use Test::More;

if($ENV{RELEASE_TESTING}) {
	use Test::Requires {
		'warnings::unused' => 0.04
	};
}

BEGIN {
	if($ENV{RELEASE_TESTING}) {
		use_ok('CGI::Buffer');
		use warnings::unused -global;
	}
}

if(not $ENV{RELEASE_TESTING}) {
	plan(skip_all => 'Author tests not required for installation');
} else {
	plan tests => 1;
}
