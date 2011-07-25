package CGI::Buffer;

use strict;
use warnings;

use MD5;
use IO::String;
use Compress::Zlib;
use CGI::Info;

=head1 NAME

CGI::Buffer - Speed the output of a CGI Program

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

CGI::Buffer speeds the output of CGI programs by making use of client and
server caches nearly seemlessly.

To make use of client caches, that is to say to reduce needless calls to
your server asking for the same data, all you need to do is to include the
package, and it does the rest.

    use CGI::Buffer;

    ...

To also make use of server caches, that is to say to save regenerating output
when different clients ask you for the same data,
you will need to create a cache,
but that's simple:

    use CGI::Buffer;
    use CHI;

    # Put this at the top before you output anything
    CGI::Buffer::set_options(
	cache => CHI->new(driver => 'File');
    );
    if(CGI::Buffer::is_cached()) {
	exit;
    }

    ...

=head1 SUBROUTINES/METHODS

=cut

our $generate_etag = 1;
our $compress_content = 1;
our $optimise_content = 0;
our $cache;

BEGIN {
	use Exporter();
	use vars qw($VERSION $buf $pos $headers $header $header_name $encoding
				$header_value $body @content_type $etag $send_body @o
				$i);

	$CGI::Buffer::buf = IO::String->new;
	$CGI::Buffer::old_buf = select($CGI::Buffer::buf);
}

END {
	select($CGI::Buffer::old_buf);
	$pos = $CGI::Buffer::buf->getpos;
	$CGI::Buffer::buf->setpos(0);
	read($CGI::Buffer::buf, $buf, $pos);
	($headers, $body) = split /\r?\n\r?\n/, $buf, 2;

	unless($headers) {
		# There was no output
		return;
	}
	if($ENV{'REQUEST_METHOD'} && ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		$send_body = 0;
	} else {
		$send_body = 1;
	}

	foreach my $header (split(/\r?\n/, $headers)) {
		($header_name, $header_value) = split /\:\s*/, $header, 2;
		if (lc($header_name) eq 'content-type') {
			@content_type = split /\//, $header_value, 2;
		}
	}

	if($optimise_content && (lc($content_type[0]) eq 'text') && (lc($content_type[1]) =~ /^html/)) {
		$body =~ s/\s\s*?/ /gm;
		$body =~ s/\r\n/\n/gm;
		$body =~ s/\n\s/\n/gm;
		$body =~ s/\s\n/\n/gm;
		$body =~ s/\n\n*?/\n/gm;

		my $i = CGI::Info->new();

		my $href = $i->host_name();
		my $protocol = $i->protocol();

		unless($protocol) {
			$protocol = 'http';
		}

		$body =~ s/<a\s+?href="$protocol:\/\/$href"/<a href="\//gim;

		# TODO: <img border=0 src=...>
		$body =~ s/<img\s+?src="$protocol:\/\/$href"/<img src="\//gim;
	}

	if($compress_content && $ENV{'HTTP_ACCEPT_ENCODING'}) {
		foreach my $encoding ('x-gzip', 'gzip') {
			$_ = lc($ENV{'HTTP_ACCEPT_ENCODING'});
			if (m/$encoding/i && lc($content_type[0]) eq 'text') {
				$body = Compress::Zlib::memGzip($body);
				push @o, "Content-Encoding: $encoding";
				push @o, "Vary: Accept-Encoding";
				last;
			}
		}
	}

	if($ENV{'SERVER_PROTOCOL'} && ($ENV{'SERVER_PROTOCOL'} eq 'HTTP/1.1')) {
		if($generate_etag) {
			$etag = '"' . MD5->hexhash($body) . '"';
			push @o, "ETag: $etag";
			if ($ENV{'HTTP_IF_NONE_MATCH'}) {
				if ($etag =~ m/$ENV{'HTTP_IF_NONE_MATCH'}/) {
					push @o, "Status: 304 Not Modified";
					push @o, "";
					$send_body = 0;
				}
			}
		}
	}

	if($send_body) {
		if($cache) {
			my $key = _generate_key();

			if(!defined($body)) {
				$body = $cache->get("CGI::Buffer $key");
			} else {
				$cache->set("CGI::Buffer $key", $body, 600);
			}
		}
		push @o, "Content-Length: " . length($body);
		push @o, $headers;
		push @o, "";

		push @o, $body;
	}

	print join("\r\n", @o);
}

# Create a key for the cache
sub _generate_key {
	my $i = CGI::Info->new();
	return $i->script_name() . ' ' . $i->params();
}

=head2 set_options

Sets the options.

    # Put this toward the top of your program before you do anything
    # By default, generate_tag and compress_content are both ON and
    # optimise_content is OFF
    CGI::Buffer::set_options(
	generate_etag => 1,
	compress_content => 1,
	optimise_content => 0,
	cache => CHI->new(driver => 'File');
    );

=cut

sub set_options {
	my %params = @_;

	if(defined($params{generate_etag})) {
		$generate_etag = $params{generate_etag};
	}
	if(defined($params{compress_content})) {
		$compress_content = $params{compress_content};
	}
	if(defined($params{optimise_content})) {
		$optimise_content = $params{optimise_content};
	}
	if(defined($params{cache})) {
		$cache = $params{cache};
	}
}

=head2 is_cached

Returns true if the output is cached.

    # Put this toward the top of your program before you do anything
    CGI::Buffer::set_options(
	cache => CHI->new(driver => 'File');
    );
    if(CGI::Buffer::is_cached()) {
	exit;
    }

=cut

sub is_cached {
	my $key = _generate_key();

	return $cache->get("CGI::Buffer $key") ? 1 : 0;
}

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

=head1 BUGS

There are no real tests because I haven't yet worked out how to capture the
output that a module outputs at the END stage to check if it's outputting the
correct data.

Mod_deflate can confuse this when comopressing output. Ensure that deflation is
off for .pl files:

    SetEnvIfNoCase Request_URI \.(?:gif|jpe?g|png|pl)$ no-gzip dont-vary

Please report any bugs or feature requests to C<bug-cgi-info at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Buffer>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.




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

Copyright 2010-2011 Nigel Horne.

This program is released under the following licence: GPL

The licence for cgi_buffer is:

    "(c) 2000 Copyright Mark Nottingham <mnot@pobox.com>

    This software may be freely distributed, modified and used,
    provided that this copyright notice remain intact.

    This software is provided 'as is' without warranty of any kind."

=cut

1; # End of CGI::Buffer
