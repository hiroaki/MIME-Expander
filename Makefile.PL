use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'MIME::Expander',
    'VERSION_FROM'  => 'lib/MIME/Expander.pm', # finds $VERSION
    'PREREQ_PM'     => {
        'Test::More'                => '0.32',
        'File::MMagic'              => '1.29',
        'Email::MIME'               => '1.905',
        'Email::MIME::ContentType'  => 0,
        'MIME::Type'                => '0.12',
        'Module::Load'              => '0.22',
        'Module::Pluggable'         => 0,
        'Archive::Tar'              => '1.82',
        'IO::Scalar'                => '2.110',
        'IO::Uncompress::Unzip'     => '2.048',
        'MIME::Type::FileName'      => '1.00',
        },
    );
