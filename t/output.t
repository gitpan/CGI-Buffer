#!perl -w

# Test if CGI::Buffer adds Content-Length and Etag headers, also simple
# check that optimise_content and gzips does something.

# TODO: check optimise_content and gzips do the *right* thing
# TODO: check ETags are correct

use strict;
use warnings;

use Test::More tests => 34;
use File::Temp;
# use Test::NoWarnings;	# HTML::Clean has them

BEGIN {
	use_ok('CGI::Buffer');
}

OUTPUT: {
	delete $ENV{'HTTP_ACCEPT_ENCODING'};
	delete $ENV{'SERVER_PROTOCOL'};

	my $tmp = File::Temp->new();
	print $tmp "use strict;\n";
	print $tmp "use CGI::Buffer;\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY>   Hello World</BODY></HTML>\\n\";\n";

	open(my $fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	my $keep = $_;
	undef $/;
	my $output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	my $length = $1;
	ok($output =~ /<HTML><BODY>   Hello World<\/BODY><\/HTML>/m);
	ok($output !~ /^Content-Encoding: gzip/m);
	ok($output !~ /^ETag: "/m);

	my ($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);

	$tmp = File::Temp->new();
	print $tmp "use CGI::Buffer;\n";
	print $tmp "CGI::Buffer::set_options(optimise_content => 1);\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY>    Hello World</BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;
	# Extra spaces should have been removed
	ok($output =~ /<HTML><BODY> Hello World<\/BODY><\/HTML>/mi);
	ok($output !~ /^Content-Encoding: gzip/m);
	ok($output !~ /^ETag: "/m);

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(defined($headers));
	ok(defined($body));
	ok(length($body) eq $length);

	$ENV{'HTTP_ACCEPT_ENCODING'} = 'gzip';

	$tmp = File::Temp->new();
	print $tmp "use CGI::Buffer;\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY>Hello World</BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;
	# It's gzipped, so it won't include this
	ok($output !~ /<HTML><BODY>Hello World<\/BODY><\/HTML>/m);
	ok($output =~ /^Content-Encoding: gzip/m);
	ok($output !~ /^ETag: "/m);

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);

	$ENV{'SERVER_PROTOCOL'} = 'HTTP/1.1';

	$tmp = File::Temp->new();
	if($ENV{'PERL5LIB'}) {
		foreach (split(':', $ENV{'PERL5LIB'})) {
			print $tmp "use lib '$_';\n";
		}
	}
	print $tmp "use CGI::Buffer;\n";
	print $tmp "CGI::Buffer::set_options(optimise_content => 1);\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY>Hello World</BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;
	ok($output !~ /<HTML><BODY>Hello World<\/BODY><\/HTML>/m);
	ok($output =~ /^Content-Encoding: gzip/m);
	ok($output =~ /ETag: "/m);

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);

	#..........................................
	delete $ENV{'SERVER_PROTOCOL'};
	delete $ENV{'HTTP_ACCEPT_ENCODING'};

	$ENV{'SERVER_NAME'} = 'www.example.com';

	$tmp = File::Temp->new();
	if($ENV{'PERL5LIB'}) {
		foreach (split(':', $ENV{'PERL5LIB'})) {
			print $tmp "use lib '$_';\n";
		}
	}
	print $tmp "use CGI::Buffer;\n";
	print $tmp "CGI::Buffer::set_options(optimise_content => 1);\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY><A HREF=\\\"http://www.example.com\\\">Click</A></BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output !~ /www.example.com/m);
	ok($output =~ /href="\/"/m);
	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);

	#..........................................
	$tmp = File::Temp->new();
	if($ENV{'PERL5LIB'}) {
		foreach (split(':', $ENV{'PERL5LIB'})) {
			print $tmp "use lib '$_';\n";
		}
	}
	print $tmp "use CGI::Buffer;\n";
	print $tmp "CGI::Buffer::set_options(optimise_content => 1);\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY><A HREF=\\\"http://www.example.com/foo.htm\\\">Click</A></BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output !~ /www.example.com/m);
	ok($output =~ /href="\/foo.htm"/m);
	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);

	#..........................................
	$tmp = File::Temp->new();
	if($ENV{'PERL5LIB'}) {
		foreach (split(':', $ENV{'PERL5LIB'})) {
			print $tmp "use lib '$_';\n";
		}
	}
	print $tmp "use CGI::Buffer;\n";
	print $tmp "CGI::Buffer::set_options(optimise_content => 1);\n";
	print $tmp "print \"Content-type: text/html; charset=ISO-8859-1\";\n";
	print $tmp "print \"\\n\\n\";\n";
	print $tmp "print \"<HTML><BODY><TABLE><TR><TD>foo</TD>  <TD>bar</TD></TR></TABLE></BODY></HTML>\\n\";\n";

	open($fout, '-|', "$^X -Iblib/lib " . $tmp->filename);

	$keep = $_;
	undef $/;
	$output = <$fout>;
	$/ = $keep;

	close $tmp;

	ok($output =~ /<TD>foo<\/TD><TD>bar<\/TD>/mi);
	ok($output =~ /^Content-Length:\s+(\d+)+/m);
	$length = $1;

	($headers, $body) = split /\r?\n\r?\n/, $output, 2;
	ok(length($body) eq $length);
}
