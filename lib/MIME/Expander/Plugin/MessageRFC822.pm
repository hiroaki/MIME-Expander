package MIME::Expander::Plugin::MessageRFC822;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use parent qw(MIME::Expander::Plugin);
__PACKAGE__->mk_classdata('ACCEPT_TYPES' => [qw(
    message/rfc822
    )]);

use Email::MIME;

sub expand {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my @parts = (Email::MIME->new(
        ref $contents eq 'SCALAR' ? $contents : \$contents
        ));
    while( my $part = shift @parts ){
        if( 1 < $part->parts ){
            push @parts, $part->subparts;
        }else{
            ++$c;
            $callback->( \$part->body, {
                filename => $part->filename,
                } ) if( ref $callback eq 'CODE' );
        }
    }

    return $c;
}

1;
__END__


=pod

=head1 NAME

MIME::Expander::Plugin::MessageRFC822 - a plugin for MIME::Expander

=head1 SYNOPSIS

    my $expander = MIME::Expander::Plugin::MessageRFC822->new;
    $expander->expand(\$data, sub {
            my $ref_expanded_data = shift;
            my $metadata = shift || {};
            print $metadata->{content_type}, "\n";
            print $metadata->{filename}, "\n";
        });

=head1 DESCRIPTION

Expand data that media type is "message/rfc822".

=head1 SEE ALSO

L<MIME::Expander::Plugin>

L<Email::MIME>

=cut
