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

    while( my $status = $uzip->nextStream ){

        die "Error processing as zip: $!"
            if( $status < 0 );

        my $bytes;
        my $buff;
        1 while( 0 < ($bytes = $uzip->read($buff)) );

        last if( $bytes < 0 );

        $callback->( \$buff, {
            filename => $uzip->getHeaderInfo->{Name},
            } ) if( ref $callback eq 'CODE' );
        ++$c;
    }

    return $c;
}

1;
__END__
