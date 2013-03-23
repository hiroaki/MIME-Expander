package MIME::Expander::Plugin::ApplicationXBzip2;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use parent qw(MIME::Expander::Plugin);
__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    application/x-bzip2
    )]);

use IO::Uncompress::Bunzip2;

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my $z = IO::Uncompress::Bunzip2->new(\$contents, Append => 1) 
        or die "bzip2 failed: $IO::Uncompress::Bunzip2::Bunzip2Error";

    my $buf;
    1 while( 0 < $z->read($buf) );
    
    my $h = $z->getHeaderInfo || {};
    $callback->( \$buf, {
        filename => $h->{Name},
        } ) if( ref $callback eq 'CODE' );
    ++$c;

    return $c;
}

1;
__END__


=pod

=head1 NAME

MIME::Expander::Plugin::ApplicationXBzip2 - a plugin for MIME::Expander

=head1 SYNOPSIS

    my $expander = MIME::Expander::Plugin::ApplicationXBzip2->new;
    $expander->expand(\$data, sub {
            my $ref_expanded_data = shift;
            my $metadata = shift || {};
            print $metadata->{content_type}, "\n";
            print $metadata->{filename}, "\n";
        });

=head1 DESCRIPTION

Expand data that media type is "application/x-bzip2".

=head1 SEE ALSO

L<MIME::Expander>
L<MIME::Expander::Plugin>
L<IO::Uncompress::Bunzip2>

=cut
