package MIME::Expander::Plugin;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use base qw(Class::Data::Inheritable);
use Email::MIME;

__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    )]);

sub new {
    my $class = shift;
    bless {}, (ref $class || $class);
}

sub accepts {
    my $self        = shift;
    my $type        = shift or return ();
    for ( @{$self->ACCEPT_TYPES} ){
        return 1 if( $type eq $_ );
    }
    return ();
}

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    $callback->( \$contents ) if( ref $callback eq 'CODE' );
    ++$c;

    return $c;
}

1;
__END__
