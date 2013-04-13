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

    my $uzip = IO::Uncompress::Unzip->new(
        ref $contents eq 'SCALAR' ? $contents : \$contents
        , Append => 1)
        or die "unzip failed: $IO::Uncompress::Unzip::UnzipError\n";

    my $status;
    for( $status = 1; 0 < $status; $status = $uzip->nextStream ){

        die "Error processing as zip: $!"
            if( $status < 0 );

        my $bytes;
        my $buff;
        1 while( 0 < ($bytes = $uzip->read($buff)) );

        last if( $bytes < 0 );

        my $name = $uzip->getHeaderInfo->{Name};
        next if( $name and $name =~ m,/$, );
        
        $callback->( \$buff, {
            filename => $name,
            } ) if( ref $callback eq 'CODE' );
        ++$c;
    }

    return $c;
}

1;
__END__


=pod

=head1 NAME

MIME::Expander::Plugin::ApplicationZip - a plugin for MIME::Expander

=head1 SYNOPSIS

    my $expander = MIME::Expander::Plugin::ApplicationZip->new;
    $expander->expand(\$data, sub {
            my $ref_expanded_data = shift;
            my $metadata = shift || {};
            print $metadata->{content_type}, "\n";
            print $metadata->{filename}, "\n";
        });

=head1 DESCRIPTION

Expand data that media type is "application/zip" or "application/x-zip".

=head1 SEE ALSO

L<MIME::Expander::Plugin>

L<IO::Uncompress::Unzip>

=cut
