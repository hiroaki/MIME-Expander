package MIME::Expander::Plugin::ApplicationTar;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use parent qw(MIME::Expander::Plugin);
__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    application/tar
    application/x-tar
    )]);

use Archive::Tar;
use IO::Scalar;

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my $iter = Archive::Tar->iter(IO::Scalar->new(
        ref $contents eq 'SCALAR' ? $contents : \$contents
        ));
    while( my $f = $iter->() ){
        if( $f->has_content and $f->validate ){
            $callback->( $f->get_content_by_ref, {
                filename => $f->full_path,
                } ) if( ref $callback eq 'CODE' );
            ++$c;
        }
    }

    return $c;
}

1;
__END__


=pod

=head1 NAME

MIME::Expander::Plugin::ApplicationTar - a plugin for MIME::Expander

=head1 SYNOPSIS

    my $expander = MIME::Expander::Plugin::ApplicationTar->new;
    $expander->expand(\$data, sub {
            my $ref_expanded_data = shift;
            my $metadata = shift || {};
            print $metadata->{content_type}, "\n";
            print $metadata->{filename}, "\n";
        });

=head1 DESCRIPTION

Expand data that type is "application/tar" or "application/x-tar".

=head1 SEE ALSO

L<MIME::Expander::Plugin>

L<Archive::Tar>

=cut
