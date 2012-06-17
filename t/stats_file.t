#!perl -w

use strict;
use warnings;

use Test::More tests => 7;
use File::Temp;
use Compress::Zlib;
# use Test::NoWarnings;	# HTML::Clean has them

BEGIN {
	use_ok('CGI::Buffer');
}

STATS_FILE: {
	if(-r '/tmp/stats_file') {
		# Race condition, yada yada
		plan skip_all => '/tmp/stats_file exists, not_testing';
		exit;
	}
	$ENV{'HTTP_ACCEPT_ENCODING'} = 'gzip';
	$ENV{'SERVER_PROTOCOL'} = 'HTTP/1.1';

	my $tmp = File::Temp->new();
	print $tmp "use strict;\n";
	print $tmp "use CGI::Buffer {stats_file => '/tmp/stats_file', generate_etag => 1};\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY>Hello World</BODY></HTML>\\n\";\n";

	open(my $fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	my $keep = $_;
	undef $/;
	my $output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /^Content-Length:\s+(\d+)/m);
	ok($output =~ /^Content-Encoding: gzip/m);
	ok($output =~ /^ETag: "/m);

	my $found_etag = 0;
	my $found_send_body = 0;

	open(my $fin, '<', '/tmp/stats_file');
	ok(defined($fin));
	while(<$fin>) {
		if(/^ETag:/m) {
			$found_etag++;
		}
		if(/send_body = 1/m) {
			$found_send_body++;
		}
	}
	close $fin;
	unlink('/tmp/stats_file');

	ok($found_etag == 1);
	ok($found_send_body == 1);
}
