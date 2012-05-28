package CGI::Buffer;

use strict;
use warnings;

use Digest::MD5;
use IO::String;
use CGI::Info;
use Carp;
use Encode;
use DateTime;
use HTTP::Date;

=head1 NAME

CGI::Buffer - Optimise the output of a CGI Program

=head1 VERSION

Version 0.44

=cut

our $VERSION = '0.44';

=head1 SYNOPSIS

CGI::Buffer optimises CGI programs by compressing output to speed up the
transmission and by nearly seamlessly making use of client and server caches.

To make use of client caches, that is to say to reduce needless calls to
your server asking for the same data, all you need to do is to include the
package, and it does the rest.

    use CGI::Buffer;
    # ...

To also make use of server caches, that is to say to save regenerating output
when different clients ask you for the same data,
you will need to create a cache.
But that's simple:

    use CGI::Buffer;
    use CHI;

    # Put this at the top before you output anything
    CGI::Buffer::init(
	cache => CHI->new(driver => 'File')
    );
    if(CGI::Buffer::is_cached()) {
	exit;
    }

    # ...

=head1 SUBROUTINES/METHODS

=cut

use constant MIN_GZIP_LEN => 32;

our $generate_etag = 1;
our $generate_last_modified = 1;
our $compress_content = 1;
our $optimise_content = 0;
our $cache;
our $cache_age;
our $cache_key;
our $info;

BEGIN {
	use Exporter();
	use vars qw($VERSION $buf $pos $headers $header $header_name
				$header_value $body @content_type $etag $send_body @o
				$send_headers);

	$CGI::Buffer::buf = IO::String->new;
	$CGI::Buffer::old_buf = select($CGI::Buffer::buf);
}

END {
	select($CGI::Buffer::old_buf);
	$pos = $CGI::Buffer::buf->getpos;
	$CGI::Buffer::buf->setpos(0);
	read($CGI::Buffer::buf, $buf, $pos);
	($headers, $body) = split /\r?\n\r?\n/, $buf, 2;

	unless($headers || is_cached()) {
		# There was no output
		return;
	}
	if($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		$send_body = 0;
	} else {
		$send_body = 1;
	}
	$send_headers = 1;

	if($headers) {
		foreach my $header (split(/\r?\n/, $headers)) {
			($header_name, $header_value) = split /\:\s*/, $header, 2;
			if (lc($header_name) eq 'content-type') {
				@content_type = split /\//, $header_value, 2;
			}
		}
	}

	if(defined($body) && (length($body) == 0)) {
		$body = undef;
	}

	if($optimise_content && defined($content_type[0]) && (lc($content_type[0]) eq 'text') && (lc($content_type[1]) =~ /^html/) && defined($body)) {
		# require HTML::Clean;
		require HTML::Packer;	# Overkill using HTML::Clean and HTML::Packer...

                $body =~ s/\r\n/\n/gs;
                $body =~ s/\s+\n/\n/gs;
                $body =~ s/\n+/\n/gs;
                $body =~ s/\<\/option\>\s\<option/\<\/option\>\<option/gis;
                $body =~ s/\<\/div\>\s\<div/\<\/div\>\<div/gis;
                $body =~ s/\<\/p\>\s\<\/div/\<\/p\>\<\/div/gis;
                $body =~ s/\s+\<p\>|\<p\>\s+/\<p\>/im;  # TODO <p class=
		$body =~ s/\s+\<\/p\>|\<\/p\>\s+/\<\/p\>/gis;
                $body =~ s/\s+\<\/html/\<\/html/is;
                $body =~ s/\s+\<\/body/\<\/body/is;
                $body =~ s/\n\s+|\s+\n/\n/g;
                $body =~ s/\t+/ /g;
                $body =~ s/\s(\<.+?\>\s\<.+?\>)/$1/;
                $body =~ s/(\<.+?\>\s\<.+?\>)\s/$1/;
                $body =~ s/\<p\>\s/\<p\>/gi;
                $body =~ s/\<\/p\>\s\<p\>/\<\/p\>\<p\>/gi;
                $body =~ s/\<\/tr\>\s\<tr\>/\<\/tr\>\<tr\>/gi;
                $body =~ s/\<\/td\>\s\<\/tr\>/\<\/td\>\<\/tr\>/gi;
		$body =~ s/\<\/td\>\s*\<td\>/\<\/td\>\<td\>/gis;
                $body =~ s/\<\/tr\>\s\<\/table\>/\<\/tr\>\<\/table\>/gi;
                $body =~ s/\<br\s?\/?\>\s?\<p\>/\<p\>/gi;
                $body =~ s/\<br\>\s/\<br\>/gi;
                $body =~ s/\<br\s?\/\>\s/\<br \/\>/gi;
                $body =~ s/\s+\<p\>/\<p\>/gi;
                $body =~ s/\s+\<script/\<script/gi;
                $body =~ s/\<td\>\s+/\<td\>/gi;
		$body =~ s/\s+\<a\s+href="(.+?)"\>\s+/ <a href="$1">/gis;
                $body =~ s/\s\s/ /gs;

		unless(defined($info)) {
			$info = CGI::Info->new();
		}

		my $href = $info->host_name();
		my $protocol = $info->protocol();

		unless($protocol) {
			$protocol = 'http';
		}

		$body =~ s/<a\s+?href="$protocol:\/\/$href"/<a href="\/"/gim;
		$body =~ s/<a\s+?href="$protocol:\/\/$href/<a href="/gim;

		# TODO: <img border=0 src=...>
		$body =~ s/<img\s+?src="$protocol:\/\/$href"/<img src="\/"/gim;
		$body =~ s/<img\s+?src="$protocol:\/\/$href/<img src="/gim;

		# Don't use HTML::Clean because of RT402
		# my $h = new HTML::Clean(\$body);
		# # $h->compat();
		# $h->strip();
		# my $ref = $h->data();

		my $packer = HTML::Packer->init();
		# Don't always do javascript 'best' since it's confused by
		# the common <!-- HIDE technique.
		# See https://github.com/nevesenin/javascript-packer-perl/issues/1#issuecomment-4356790
		my $options = {
			remove_comments => 1,
			remove_newlines => 0,
			do_stylesheet => 'minify'
		};
		if($optimise_content >= 2) {
			$options->{do_javascript} = 'best';
			$body =~ s/(<script.*>)\s*<!--/$1/gi;
			$body =~ s/\/\/-->\s*<\/script>/<\/script>/gi;
		}
		$body = HTML::Packer->init()->minify(\$body, $options);
		if($optimise_content >= 2) {
			# Change document.write("a"); document.write("b")
			# into document.write("a"+"b");
			# This will only change one occurance per script
			$body =~ s/<script\s*?type\s*?=\s*?"text\/javascript"\s*?>(.*?)document\.write\((.+?)\);\s*?document\.write\((.+?)\)/<script type="text\/JavaScript">${1}document.write($2+$3)/igs;
		}
	}

	# Generate the eTag before compressing, since the compressed data
	# includes the mtime field which changes thus causing a different
	# Etag to be generated
	if($ENV{'SERVER_PROTOCOL'} && ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1') && defined($body)) {
		if($generate_etag) {
			# encode to avoid "Wide character in subroutine entry"
			$etag = '"' . Digest::MD5->new->add(Encode::encode_utf8($body))->hexdigest() . '"';
			push @o, "ETag: $etag";
			if ($ENV{'HTTP_IF_NONE_MATCH'}) {
				if ($etag =~ m/$ENV{'HTTP_IF_NONE_MATCH'}/) {
					push @o, "Status: 304 Not Modified";
					$send_body = 0;
					$send_headers = 0;
				}
			}
		}
	}

	my $isgzipped = 0;
	my $encoding = _should_gzip();

	if(length($encoding) > 0) {
		if(defined($body)) {
			if($ENV{'Range'} && !$cache) {
				# TODO: Partials
				if($ENV{'Range'} =~ /^bytes=(\d*)-(\d*)/) {
					if($1 && $2) {
						$body = substr($body, $1, $2-$1);
					} elsif($1) {
						$body = substr($body, $1);
					} elsif($2) {
						$body = substr($body, 0, $2);
					}
				}
			}
			if(length($body) >= MIN_GZIP_LEN) {
				require Compress::Zlib;
				Compress::Zlib->import;

				# Avoid 'Wide character in memGzip'
				$body = Compress::Zlib::memGzip(\encode_utf8($body));
				push @o, "Content-Encoding: $encoding";
				push @o, "Vary: Accept-Encoding";
			}
		}
		$isgzipped = 1;
	}

	if($cache) {
		my $key = _generate_key();

		# Maintain separate caches for gzipped and non gzipped so that
		# browsers get what they ask for and can support
		if(!defined($body)) {
			if($send_body) {
				$body = $cache->get("CGI::Buffer/$key/$isgzipped");
				if($ENV{'SERVER_PROTOCOL'} &&
				  ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1') &&
				  defined($body)) {
					if($ENV{'HTTP_IF_NONE_MATCH'}) {
						if(!defined($etag)) {
							$etag = '"' . Digest::MD5->new->add(Encode::encode_utf8($body))->hexdigest() . '"';
						}
						if ($etag =~ m/$ENV{'HTTP_IF_NONE_MATCH'}/) {
							push @o, "Status: 304 Not Modified";
							$send_body = 0;
							$send_headers = 0;
						}
					}
					if($ENV{'IF_MODIFIED_SINCE'} && $send_body) {
						my $r = DateTime->new($ENV{'IF_MODIFIED_SINCE'});
						my $a = DateTime->new($cache->get_object("CGI::Buffer/$key/$isgzipped")->created_at());

						if($r >= $a) {
							push @o, "Status: 304 Not Modified";
							$send_body = 0;
							$send_headers = 0;
						}
					}
				}
			}
			if($send_headers) {
				my $hkey = "CGI::Buffer/$key/headers";
				$headers = $cache->get($hkey);
				if($generate_last_modified) {
					push @o, "Last-Modified: " . HTTP::Date::time2str($cache->get_object($hkey)->created_at());
				}
				push @o, "X-CGI-Buffer-$VERSION: Hit";
			}
		} else {
			unless($cache_age) {
				# It would be great if CHI::set() allowed
				# the time to be 'lru' for least recently
				# used.
				$cache_age = '10 minutes';
			}
			$cache->set("CGI::Buffer/$key/$isgzipped", $body, $cache_age);
			if(scalar(@o)) {
				$cache->set("CGI::Buffer/$key/headers", "$headers\r\n" . join("\r\n", @o), $cache_age);
			} else {
				$cache->set("CGI::Buffer/$key/headers", $headers, $cache_age);
			}
			if($generate_last_modified) {
				push @o, "Last-Modified: " . HTTP::Date::time2str(time);
			}
			push @o, "X-CGI-Buffer-$VERSION: Miss";
		}
	}

	my $body_length = defined($body) ? length($body) : 0;

	if($send_headers) {
		if(defined($headers) && length($headers)) {
			push @o, $headers;
			if($body && $send_body) {
				push @o, "Content-Length: $body_length";
			}
		} else {
			push @o, "X-CGI-Buffer-$VERSION: No headers";
		}
	}

	if($body_length && $send_body) {
		push @o, '';
		push @o, $body;
	}

	# if(defined(@o) && (scalar @o)) {
	if(scalar @o) {
		print join("\r\n", @o);
	}

	if((!$send_body) || !defined($body)) {
		print "\r\n\r\n";
	}
}

# Create a key for the cache
sub _generate_key {
	if($cache_key) {
		return $cache_key;
	}
	unless(defined($info)) {
		$info = CGI::Info->new();
	}

	# TODO: Use CGI::Lingua so that different languages are stored in
	#	different caches
	return $info->domain_name() . '/' . $info->script_name() . '/' . $info->as_string();
}

=head2 init

Set various options and override default values.

    # Put this toward the top of your program before you do anything
    # By default, generate_tag and compress_content are both ON and
    # optimise_content is OFF.  Set optimise_content to 2 to do aggressive
    # JavaScript optimisations which may fail.
    use CGI::Buffer;
    CGI::Buffer::init(
	generate_etag => 1,	# make good use of client's cache
	generate_last_modified => 1,	# more use of client's cache
	compress_content => 1,	# if gzip the output
	optimise_content => 0,	# optimise your program's HTML, CSS and JavaScript
	cache => CHI->new(driver => 'File'),	# cache requests
	cache_key => 'string'	# key for the cache
    );

If no cache_key is given, one will be generated which may not be unique.
The cache_key should be a unique value dependent upon the values set by the
browser.

The cache object will be an instantiation of a class that understands get,
set, created_at and is_valid, such as L<CHI>.

To generate a last_modified header, you must give a cache object.

Init allows a reference of the options to be passed. So both of these work:
    use CGI::Buffer;
    #...
    CGI::Buffer::init(generate_etag => 1);
    CGI::Buffer::init({ generate_etag => 1 });

Generally speaking, passing by reference is better since it copies less on to
the stack.

Alternatively you can give the options when loading the package:
    use CGI::Buffer { optimise_content => 1 };

=cut

sub init {
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	# Safe options - can be called at any time
	if(defined($params{generate_etag})) {
		$generate_etag = $params{generate_etag};
	}
	if(defined($params{generate_last_modified})) {
		$generate_last_modified = $params{generate_last_modified};
	}
	if(defined($params{compress_content})) {
		$compress_content = $params{compress_content};
	}
	if(defined($params{optimise_content})) {
		$optimise_content = $params{optimise_content};
	}

	# Unsafe options - must be called before output has been started
	my $pos = $CGI::Buffer::buf->getpos;
	if($pos > 0) {
		# Must do Carp::carp instead of carp for Test::Carp
		Carp::carp "Too late to call init, $pos characters have been printed";
		return;
	}
	unless(defined($ENV{'NO_CACHE'}) || defined($ENV{'NO_STORE'})) {
		if(defined($params{cache})) {
			if(defined($ENV{'HTTP_CACHE_CONTROL'})) {
				my $control = $ENV{'HTTP_CACHE_CONTROL'};
				unless(($control eq 'no-store') || ($control eq 'no-cache')) {
					if($control =~ /^max-age\s*=\s*(\d+)$/) {
						# There is an argument not to do this
						# since one client will affect others
						$cache_age = "$1 seconds";
					}
					$cache = $params{cache};
				}
			} else {
				$cache = $params{cache};
			}
		}
		if(defined($params{cache_key})) {
			$cache_key = $params{cache_key};
		}
	}
}

sub import {
	# my $class = shift;
	shift;

	return unless @_;

	init(@_);
}

=head2 set_options

Synonym for init, kept for historical reasons.

=cut

sub set_options {
	my %params = @_;

	init(%params);
}

=head2 is_cached

Returns true if the output is cached. If it is then it means that all of the
expensive routines in the CGI script can be by-passed because we already have
the result stored in the cache.

    # Put this toward the top of your program before you do anything

    # Example key generation - use whatever you want as something
    # unique for this call, so that subsequent calls with the same
    # values match something in the cache
    use CGI::Info;
    use CGI::Lingua;

    my $i = CGI::Info->new();
    my $l = CGI::Lingua->new(supported => ['en']);

    # To use server side caching you must give the cache argument, however
    # the cache_key argument is optional - if you don't give one then one will
    # be generated for you
    CGI::Buffer::init(
	cache => CHI->new(driver => 'File'),
	cache_key => $i->domain_name() . '/' . $i->script_name() . '/' . $i->as_string() . '/' . $l->language()
    );
    if(CGI::Buffer::is_cached()) {
	# Output will be retrieved from the cache and sent automatically
	exit;
    }
    # Not in the cache, so now do our expensive computing to generate the
    # results
    print "Content-type: text/html\n";
    # ...

=cut

sub is_cached {
	unless($cache) {
		return 0;
	}
	my $key = _generate_key();
	my $encoding = _should_gzip();
	my $isgzipped = (length($encoding) > 0) ? 1 : 0;

	# FIXME: It is remotely possible that is_valid will succeed, and the
	#	cache expires before the above get, causing the get to possibly
	#	fail
	return $cache->is_valid("CGI::Buffer/$key/$isgzipped");
}

sub _should_gzip {
	if($compress_content && $ENV{'HTTP_ACCEPT_ENCODING'}) {
		foreach my $encoding ('x-gzip', 'gzip') {
			$_ = lc($ENV{'HTTP_ACCEPT_ENCODING'});
			if($content_type[0]) {
				if (m/$encoding/i && lc($content_type[0]) eq 'text') {
					return $encoding;
				}
			} else {
				if (m/$encoding/i) {
					return $encoding;
				}
			}
		}
	}

	return '';
}

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

=head1 BUGS

When using L<Template>, ensure that you don't use it to output to STDOUT, instead you
will need to capture into a variable and print that.
For example:

    my $output;
    $template->process($input, $vars, \$output) || ($output = $template->error());
    print $output;

Can produce buggy JavaScript if you use the <!-- HIDING technique.
This is a bug in L<<JavaScript::Packer>>, not CGI::Buffer.
See https://github.com/nevesenin/javascript-packer-perl/issues/1#issuecomment-4356790

Mod_deflate can confuse this when compressing output. Ensure that deflation is
off for .pl files:

    SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png|pl)$ no-gzip dont-vary

Please report any bugs or feature requests to C<bug-cgi-buffer at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Buffer>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SEE ALSO

HTML::Packer

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CGI::Buffer


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CGI-Buffer>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CGI-Buffer>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CGI-Buffer>

=item * Search CPAN

L<http://search.cpan.org/dist/CGI-Buffer/>

=back


=head1 ACKNOWLEDGEMENTS

The inspiration and code for some if this is cgi_buffer by Mark Nottingham:
http://www.mnot.net/cgi_buffer.

=head1 LICENSE AND COPYRIGHT

The licence for cgi_buffer is:

    "(c) 2000 Copyright Mark Nottingham <mnot@pobox.com>

    This software may be freely distributed, modified and used,
    provided that this copyright notice remain intact.

    This software is provided 'as is' without warranty of any kind."

The reset of the program is Copyright 2011-2012 Nigel Horne,
and is released under the following licence: GPL

=cut

1; # End of CGI::Buffer
