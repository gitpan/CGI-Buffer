use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'CGI::Buffer',
    AUTHOR              => q{Nigel Horne <njh@bandsman.co.uk>},
    VERSION_FROM        => 'lib/CGI/Buffer.pm',
    ABSTRACT_FROM       => 'lib/CGI/Buffer.pm',
    ((defined($ExtUtils::MakeMaker::VERSION) &&
     ($ExtUtils::MakeMaker::VERSION >= 6.3002))
      ? ('LICENSE'=> 'GPL')
      : ()),
    PL_FILES            => {},
    BUILD_REQUIRES => {
	'Test::Most' => 0,
	# 'Test::NoWarnings' => 0,
	'Test::TempDir' => 0,
	'DateTime' => 0,
	'Compress::Zlib' => 0,
	# 'Test::Kwalitee' => 0,
    },
    PREREQ_PM => {
	'Carp' => 0,
	'CGI::Info' => 0.42,	# Minimum version for Cygwin
	'CSS::Packer' => 0,
	'Compress::Zlib' => 0,
	'Digest::MD5' => 0,
    	'Encode' => 0,
	# 'HTML::Clean' => 0.8,
	'HTML::Packer' => 1.000,
	'IO::String' => 0,
	'JavaScript::Packer' => 1.006003,
	'HTTP::Date' => 0,
	'File::Spec' => 0,
	'Time::localtime' => 0,
	'HTML::Lint' => 0,
	'Storable' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CGI-Buffer-*' },
    META_MERGE		=> {
    	'meta-spec' => { version => 2 },
    	resources => {
    		repository => {
			type => 'git',
			url => 'git://github.com/nigelhorne/CGI-Buffer.git',
			web => 'https://github.com/nigelhorne/CGI-Buffer',
    		},
	},
    },
    MIN_PERL_VERSION	=> '5.6.2'	# Probably would work, but never tested on earlier versions than this
);
