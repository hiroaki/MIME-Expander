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

    my $iter = Archive::Tar->iter(IO::Scalar->new(\$contents));
    while( my $f = $iter->() ){
#        debug("expand_application_tar: contains: ".$f->full_path);
        if( $f->has_content and $f->validate ){
            $callback->( $f->get_content_by_ref ) if( ref $callback eq 'CODE' );
            ++$c;
        }
    }

    return $c;
}

1;
__END__
