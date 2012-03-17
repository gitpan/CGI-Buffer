use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'CGI::Buffer',
    AUTHOR              => q{Nigel Horne <njh@bandsman.co.uk>},
    VERSION_FROM        => 'lib/CGI/Buffer.pm',
    ABSTRACT_FROM       => 'lib/CGI/Buffer.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'GPL')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0.82,	# Needs new_ok
	'IO::CaptureOutput' => 0,
	'Digest::MD5' => 0,
	'IO::String' => 0,
	'Compress::Zlib' => 0,
	'CGI::Info' => 0.11,	# Needs fixed as_string and protocol
	# 'HTML::Clean' => 0.8,
	'CSS::Packer' => 0,
	'HTML::Packer' => 1.000,
	'JavaScript::Packer' => 1.006003,
	'Carp' => 0,
	'Test::Kwalitee' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CGI-Buffer-*' },
);
