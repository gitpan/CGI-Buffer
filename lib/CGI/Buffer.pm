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
use File::Spec;
use Storable;
use Time::localtime;	# For ctime

=head1 NAME

CGI::Buffer - Verify and Optimise CGI Output

=head1 VERSION

Version 0.67

=cut

our $VERSION = '0.67';

=head1 SYNOPSIS

CGI::Buffer verifies the HTML that you produce by passing it through
C<HTML::Lint>.

CGI::Buffer optimises CGI programs by compressing output to speed up the
transmission and by nearly seamlessly making use of client and server caches.

To make use of client caches, that is to say to reduce needless calls to
your server asking for the same data, all you need to do is to include the
package, and it does the rest.

    use CGI::Buffer;
    # ...

To also make use of server caches, that is to say to save regenerating output
when different clients ask you for the same data, you will need to create a
cache.
But that's simple:

    use CGI::Buffer;
    use CHI;

    # Put this at the top before you output anything
    CGI::Buffer::init(
	cache => CHI->new(driver => 'File')
    );
    if(CGI::Buffer::is_cached()) {
	# Nothing has changed - use the version in the cache
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
our $lint_content = 0;
our $cache;
our $cache_age;
our $cache_key;
our $info;
our $logger;
our $status;
our $script_mtime;
our $cobject;

BEGIN {
	use Exporter();
	use vars qw($VERSION $buf $pos $headers $header
				$body @content_type $etag
				$send_body @o);

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

	if($headers) {
		foreach my $header (split(/\r?\n/, $headers)) {
			my ($header_name, $header_value) = split /\:\s*/, $header, 2;
			if (lc($header_name) eq 'content-type') {
				@content_type = split /\//, $header_value, 2;
				last;
			}
		}
	}

	if(defined($body) && (length($body) == 0)) {
		# E.g. if header of Location is given with no body, for
		#	redirection
		$body = undef;
		$send_body = 0;	# Don't try to retrieve it
	} elsif(defined($content_type[0]) && (lc($content_type[0]) eq 'text') && (lc($content_type[1]) =~ /^html/) && defined($body)) {
		if($optimise_content) {
			# require HTML::Clean;
			require HTML::Packer;	# Overkill using HTML::Clean and HTML::Packer...

			$body =~ s/\r\n/\n/gs;
			$body =~ s/\s+\n/\n/gs;
			$body =~ s/\n+/\n/gs;
			$body =~ s/\<\/option\>\s\<option/\<\/option\>\<option/gis;
			$body =~ s/\<\/div\>\s\<div/\<\/div\>\<div/gis;
			$body =~ s/\<\/p\>\s\<\/div/\<\/p\>\<\/div/gis;
			$body =~ s/\<div\>\s+/\<div\>/gis;	# Remove spaces after <div>
			$body =~ s/\s+<\/div\>/\<\/div\>/gis;	# Remove spaces before </div>
			$body =~ s/\s+\<p\>|\<p\>\s+/\<p\>/im;  # TODO <p class=
			$body =~ s/\s+\<\/p\>|\<\/p\>\s+/\<\/p\>/gis;
			$body =~ s/<html>\s+<head>/<html><head>/gis;
			$body =~ s/\s*<\/head>\s+<body>\s*/<\/head><body>/gis;
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
			$body =~ s/\s*<a\s+href=\s+"(.+?)"\>/ <a href="$1">/gis;
			$body =~ s/\s\s/ /gs;
			$body =~ s/\s+<hr>/<hr>/gis;
			$body =~ s/<hr>\s+/<hr>/gis;
			$body =~ s/<\/li>\s+<li>/<\/li><li>/gis;
			$body =~ s/<\/li>\s+<\/ul>/<\/li><\/ul>/gis;
			$body =~ s/<ul>\s+<li>/<ul><li>/gis;

			# If we're on http://www.example.com and have a link
			# to http://www.example.com/foo/bar.htm, change the
			# link to /foo.bar.htm - there's no need to include
			# the site name in the link
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

			# TODO use URI->path_segments to change links in
			# /aa/bb/cc/dd.htm which point to /aa/bb/ff.htm to
			# ../ff.htm

			# TODO: <img border=0 src=...>
			$body =~ s/<img\s+?src="$protocol:\/\/$href"/<img src="\/"/gim;
			$body =~ s/<img\s+?src="$protocol:\/\/$href/<img src="/gim;

			# Don't use HTML::Clean because of RT402
			# my $h = new HTML::Clean(\$body);
			# # $h->compat();
			# $h->strip();
			# my $ref = $h->data();

			# Don't always do javascript 'best' since it's confused
			# by the common <!-- HIDE technique.
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
		if($lint_content) {
			require HTML::Lint;
			HTML::Lint->import;

			my $lint = HTML::Lint->new();
			$lint->parse($body);

			if($lint->errors) {
				$headers = 'Status: 500 Internal Server Error';
				@o = ('Content-type: text/plain');
				$body = '';
				foreach my $error ($lint->errors) {
					my $errtext = $error->where() . ': ' . $error->errtext() . "\n";
					warn($errtext);
					$body .= $errtext;
				}
			}
		}
	}

	$status = 200;

	if(defined($headers) && ($headers =~ /^Status: (\d+)/m)) {
		$status = $1;
	}

	# Generate the eTag before compressing, since the compressed data
	# includes the mtime field which changes thus causing a different
	# Etag to be generated
	if($ENV{'SERVER_PROTOCOL'} &&
	  ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1') &&
	  $generate_etag && defined($body)) {
		# encode to avoid "Wide character in subroutine entry"
		$etag = '"' . Digest::MD5->new->add(Encode::encode_utf8($body))->hexdigest() . '"';
		push @o, "ETag: $etag";
		if ($ENV{'HTTP_IF_NONE_MATCH'}) {
			if(($etag =~ /\Q$ENV{'HTTP_IF_NONE_MATCH'}\E/) && ($status == 200)) {
				push @o, "Status: 304 Not Modified";
				$send_body = 0;
				$status = 304;
			}
		}
	}

	my $encoding = _should_gzip();
	my $unzipped_body = $body;

	if((length($encoding) > 0) && defined($body)) {
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
				$unzipped_body = $body;
			}
		}
		if(length($body) >= MIN_GZIP_LEN) {
			require Compress::Zlib;
			Compress::Zlib->import;

			# Avoid 'Wide character in memGzip'
			my $nbody = Compress::Zlib::memGzip(\encode_utf8($body));
			if(length($nbody) < length($body)) {
				$body = $nbody;
				push @o, "Content-Encoding: $encoding";
				push @o, "Vary: Accept-Encoding";
			}
		}
	}

	if($cache) {
		my $cache_hash;
		my $key = _generate_key();

		# Cache unzipped version
		if(!defined($body)) {
			if($send_body) {
				$cobject = $cache->get_object($key);
				if(defined($cobject)) {
					$cache_hash = Storable::thaw($cobject->value());
					$headers = $cache_hash->{'headers'};
					@o = ("X-CGI-Buffer-$VERSION: Hit");
				} else {
					carp "Error retrieving data for key $key";
				}
			}

			# Nothing has been output yet, so we can check if it's
			# OK to send 304 if possible
			if($send_body && $ENV{'SERVER_PROTOCOL'} &&
			  ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1') &&
			  ($status == 200)) {
				if($ENV{'HTTP_IF_MODIFIED_SINCE'}) {
					_check_modified_since({
						since => HTTP::Date::str2time($ENV{'HTTP_IF_MODIFIED_SINCE'}),
						modified => $cobject->created_at()
					});
				}
			}
			if($send_body && ($status == 200)) {
				$body = $cache_hash->{'body'};
				if(!defined($body)) {
					# Panic
					$headers = 'Status: 500 Internal Server Error';
					@o = ('Content-type: text/plain');
					$body = "Can't retrieve body for key $key, cache_hash contains:\n";
					foreach my $k (keys %{$cache_hash}) {
						$body .= "\t$k\n";
					}
					warn($body);
					$cache->remove($key);
					carp "Can't retrieve body for key $key";
					$send_body = 0;
					$status = 500;
				}
			}
			if($send_body && $ENV{'SERVER_PROTOCOL'} &&
			  ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1') &&
			  ($status == 200)) {
				if($ENV{'HTTP_IF_NONE_MATCH'}) {
					if(!defined($etag)) {
						$etag = '"' . Digest::MD5->new->add(Encode::encode_utf8($body))->hexdigest() . '"';
					}
					if ($etag =~ /\Q$ENV{'HTTP_IF_NONE_MATCH'}\E/) {
						push @o, "Status: 304 Not Modified";
						$status = 304;
						$send_body = 0;
					}
				}
				if($send_body && (length($encoding) > 0)) {
					if(length($body) >= MIN_GZIP_LEN) {
						require Compress::Zlib;
						Compress::Zlib->import;

						# Avoid 'Wide character in memGzip'
						my $nbody = Compress::Zlib::memGzip(\encode_utf8($body));
						if(length($nbody) < length($body)) {
							$body = $nbody;
							push @o, "Content-Encoding: $encoding";
							push @o, "Vary: Accept-Encoding";
						}
					}
				}
			}
			if($cobject) {
				if($ENV{'HTTP_IF_MODIFIED_SINCE'} && ($status != 304)) {
					_check_modified_since({
						since => HTTP::Date::str2time($ENV{'HTTP_IF_MODIFIED_SINCE'}),
						modified => $cobject->created_at()
					});
				} elsif($generate_last_modified) {
					push @o, "Last-Modified: " . HTTP::Date::time2str($cobject->created_at());
				}
			}
			if(defined($headers) && ($headers =~ /^ETag: "([a-z0-9]{32})"/m)) {
				$etag = $1;
			} else {
				$etag = $cache_hash->{'etag'};
			}
			if($ENV{'HTTP_IF_NONE_MATCH'} && $send_body && ($status != 304)) {
				if(defined($etag) && ($etag =~ /\Q$ENV{'HTTP_IF_NONE_MATCH'}\E/) && ($status == 200)) {
					push @o, "Status: 304 Not Modified";
					$send_body = 0;
					$status = 304;
				}
			} elsif($generate_etag && defined($etag) && ((!defined($headers)) || ($headers !~ /^ETag: /m))) {
				push @o, "ETag: $etag";
			}
		} else {
			if($status == 200) {
				unless($cache_age) {
					# It would be great if CHI::set()
					# allowed the time to be 'lru' for least
					# recently used.
					$cache_age = '10 minutes';
				}
				$cache_hash->{'body'} = $unzipped_body;
				if($body && $send_body) {
					my $body_length = length($body);
					push @o, "Content-Length: $body_length";
				}
				if(scalar(@o)) {
					# Remember, we're storing the UNzipped
					# version in the cache
					my $c;
					if(defined($headers) && length($headers)) {
						$c = $headers . "\r\n" . join("\r\n", @o);
					} else {
						$c = join("\r\n", @o);
					}
					$c =~ s/^Content-Encoding: .+$//mg;
					$c =~ s/^Vary: Accept-Encoding.*\r?$//mg;
					$c =~ s/\n+/\n/gs;
					if(length($c)) {
						$cache_hash->{'headers'} = $c;
					}
				} elsif(defined($headers) && length($headers)) {
					$headers =~ s/^Content-Encoding: .+$//mg;
					$headers =~ s/^Vary: Accept-Encoding.*\r?$//mg;
					$headers =~ s/\n+/\n/gs;
					if(length($headers)) {
						$cache_hash->{'headers'} = $headers;
					}
				}
				if($generate_etag && defined($etag)) {
					$cache_hash->{'etag'} = $etag
				}
				$cache->set($key, Storable::freeze($cache_hash), $cache_age);
				if($generate_last_modified) {
					$cobject = $cache->get_object($key);
					if(defined($cobject)) {
						push @o, "Last-Modified: " . HTTP::Date::time2str($cobject->created_at());
					} else {
						push @o, "Last-Modified: " . HTTP::Date::time2str(time);
					}
				}
			}
			push @o, "X-CGI-Buffer-$VERSION: Miss";
		}
		# We don't need it any more, so give Perl a chance to
		# tidy it up seeing as we're in the destructor
		$cache = undef;
	}

	my $body_length = defined($body) ? length($body) : 0;

	if(defined($headers) && length($headers)) {
		# Put the original headers first, then those generated within
		# CGI::Buffer
		unshift @o, split(/\r\n/, $headers);
		if($body && $send_body) {
			my $already_done = 0;
			foreach(@o) {
				if(/^Content-Length: /) {
					$already_done = 1;
					last;
				}
			}
			unless($already_done) {
				push @o, "Content-Length: $body_length";
			}
		}
	} else {
		push @o, "X-CGI-Buffer-$VERSION: No headers";
	}

	if($body_length && $send_body) {
		push @o, '';
		push @o, $body;
	}

	if(scalar @o) {
		print join("\r\n", @o);
	}

	if((!$send_body) || !defined($body)) {
		print "\r\n\r\n";
	}
}

sub _check_modified_since {
	my $params = shift;

	my $s = $$params{since};

	my $age = _my_age();
	unless(defined($age)) {
		return;
	}
	if($age > $s) {
		# Script has been updated so it may produce different output
		return;
	}

	if($$params{modified} <= $s) {
		push @o, "Status: 304 Not Modified";
		$status = 304;
		$send_body = 0;
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
	#	Mobile/web/robot pages should be stored in different caches
	my $key = $info->domain_name() . '::' . $info->script_name() . '::' . $info->as_string();
	if($ENV{'HTTP_COOKIE'}) {
		# Different states of the client are stored in different caches
		$key .= '::' . $ENV{HTTP_COOKIE};
	}
	$key =~ s/\//::/g;
	return $key;
}

=head2 init

Set various options and override default values.

    # Put this toward the top of your program before you do anything
    # By default, generate_tag and compress_content are both ON and
    # optimise_content and lint_content are OFF.  Set optimise_content to 2 to
    # do aggressive JavaScript optimisations which may fail.
    use CGI::Buffer;
    CGI::Buffer::init(
	generate_etag => 1,	# make good use of client's cache
	generate_last_modified => 1,	# more use of client's cache
	compress_content => 1,	# if gzip the output
	optimise_content => 0,	# optimise your program's HTML, CSS and JavaScript
	cache => CHI->new(driver => 'File'),	# cache requests
	cache_key => 'string',		# key for the cache
	logger => $logger,
	lint->content => 0,	# Pass through HTML::Lint
    );

If no cache_key is given, one will be generated which may not be unique.
The cache_key should be a unique value dependent upon the values set by the
browser.

The cache object will be an object that understands get(),
set(), remove() and created_at() messages, such as an L<CHI> object.

Logger will be an object that understands debug() such as an L<Log::Log4perl>
object.

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
	if(defined($params{lint_content})) {
		$lint_content = $params{lint_content};
	}
	if(defined($params{logger})) {
		$logger = $params{logger};
	}

	# Unsafe options - must be called before output has been started
	my $pos = $CGI::Buffer::buf->getpos;
	if($pos > 0) {
		# Must do Carp::carp instead of carp for Test::Carp
		Carp::carp "Too late to call init, $pos characters have been printed";
	}
	unless(defined($ENV{'NO_CACHE'}) || defined($ENV{'NO_STORE'})) {
		if(defined($params{cache})) {
			if(defined($ENV{'HTTP_CACHE_CONTROL'})) {
				my $control = $ENV{'HTTP_CACHE_CONTROL'};
				unless(($control eq 'no-store') ||
				       ($control eq 'no-cache') ||
				       ($control eq 'private')) {
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

	if($logger) {
		$logger->debug("is_cached: looking for key = $key");
	}
	$cobject = $cache->get_object($key);
	unless($cobject) {
		if($logger) {
			$logger->debug('is_cached: not found in cache');
		}
		return 0;
	}
	unless($cache->get($key)) {
		if($logger) {
			$logger->debug('is_cached: object is in the cache but not the data');
		}
		$cobject = undef;
		return 0;
	}

	# If the script has changed, don't use the cache since we may produce
	# different output
	my $age = _my_age();
	unless(defined($age)) {
		if($logger) {
			$logger->debug("Can't determine script's age");
		}
		# Can't determine the age. Play it safe an assume we're not
		# cached
		$cobject = undef;
		return 0;
	}
	if($age > $cobject->created_at()) {
		# Script has been updated so it may produce different output
		if($logger) {
			$logger->debug('Script has been updated');
		}
		$cobject = undef;
		return 0;
	}
	if($logger) {
		$logger->debug('Script is in the cache');
	}
	return 1;
}

sub _my_age {
	if($script_mtime) {
		return $script_mtime;
	}
	unless(defined($info)) {
		$info = CGI::Info->new();
	}

	my $path = $info->script_path();
	unless(defined($path)) {
		return;
	}

	my @statb = stat($path);
	$script_mtime = $statb[9];
	return $script_mtime;
}

sub _should_gzip {
	if($compress_content && $ENV{'HTTP_ACCEPT_ENCODING'}) {
		foreach my $encoding ('x-gzip', 'gzip') {
			$_ = lc($ENV{'HTTP_ACCEPT_ENCODING'});
			if($content_type[0]) {
				if (m/$encoding/i && (lc($content_type[0]) eq 'text')) {
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

When using L<Template>, ensure that you don't use it to output to STDOUT,
instead you will need to capture into a variable and print that.
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

If you request compressed output then uncompressed output (or vice versa)
on input that produces the same output, the status will be 304. The letter of
the spec says that's wrong, so I'm noting it here, but in practice you should
not see this happen or have any difficulties because of it.

Please report any bugs or feature requests to C<bug-cgi-buffer at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Buffer>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SEE ALSO

HTML::Packer, HTML::Lint

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
