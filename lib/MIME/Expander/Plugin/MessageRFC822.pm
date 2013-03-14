package MIME::Expander::Plugin::MessageRFC822;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use parent qw(MIME::Expander::Plugin);
__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    message/rfc822
    )]);

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my @parts = ( Email::MIME->new( $contents ) );
    while( my $part = shift @parts ){
        if( 1 < $part->parts ){
            push @parts, $part->subparts;
        }else{
            ++$c;
            $callback->( \$part->body ) if( ref $callback eq 'CODE' );
        }
    }

    return $c;
}

1;
__END__
