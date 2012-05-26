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
	'Carp' => 0,
	'CGI::Info' => 0.11,	# Needs fixed as_string and protocol
	'CSS::Packer' => 0,
	'Compress::Zlib' => 0,
	'Digest::MD5' => 0,
    	'Encode' => 0,
	# 'HTML::Clean' => 0.8,
	'HTML::Packer' => 1.000,
	'IO::CaptureOutput' => 0,
	'IO::String' => 0,
	'JavaScript::Packer' => 1.006003,
	'Test::Kwalitee' => 0,
        'Test::More' => 0.82,	# Needs new_ok
	'DateTime' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CGI-Buffer-*' },
);
