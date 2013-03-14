package MIME::Expander::Plugin::ApplicationZip;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use parent qw(MIME::Expander::Plugin);
__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    application/zip
    application/x-zip
    )]);

use IO::Uncompress::Unzip;

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my $uzip = IO::Uncompress::Unzip->new(\$contents, Append => 1)
        or die "unzip failed: $IO::Uncompress::Unzip::UnzipError\n";

    my $status;
    for( $status = 1; 0 < $status; $status = $uzip->nextStream ){
 
        my $name = $uzip->getHeaderInfo->{Name};
#        debug("expand_application_zip: contains: $name");

        my $bytes;
        my $buff;
        1 while( 0 < ($bytes = $uzip->read($buff)) );

        last if( $bytes < 0 );

        $callback->( \$buff ) if( ref $callback eq 'CODE' );
        ++$c;
    }

    die "Error processing as zip: $!\n"
        if( $status < 0 );

    return $c;
}

1;
__END__
