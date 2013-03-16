package MIME::Expander;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use vars qw($DEBUG);
$DEBUG = 0;

use File::MMagic;
use Email::MIME;
use Email::MIME::ContentType ();
use Module::Load qw(load);
use Module::Pluggable sub_name => 'expanders';

my $PrefixPlugin   = 'MIME::Expander::Plugin';
my @EnabledPlugins = ();

sub import {
    my $class = shift;
    @EnabledPlugins = @_;
}

sub debug {
    shift;
    my $msg = shift or return;
    printf STDERR "# %s: %s\n", __PACKAGE__, $msg if( $DEBUG );
}

sub new {
    my $class = shift;
    $class = ref $class || $class;
    my $self = {
        expects => [],
        };
    bless $self, $class;
    return $self->init(@_);
}

sub init {
    my $self = shift;
    my $args = shift || {};
    $self->expects($args->{expects}) if( exists $args->{expects} );
    return $self;
}

sub expects {
    my $self = shift;
    return @_ ? $self->{expects} = shift : $self->{expects};
}

sub is_expected_type {
    my $self = shift;
    my $type = shift or undef;
    for my $regexp ( map { ref $_ ? $_ : qr/^$_$/ } @{$self->expects} ){
        return 1 if( $type =~ $regexp );
    }
    return ();
}

sub guess_content_type {
    File::MMagic->new->checktype_contents($_[1]) || 'application/octet-stream';
}

sub parsed_mime_type {
    my $data = Email::MIME::ContentType::parse_content_type($_[1]);
    if( $data->{discrete} and $data->{composite} ){
        return join('/',$data->{discrete}, $data->{composite});
    }
    return ();
}

sub plugin_for {
    my $self = shift;
    my $type = shift;

    my $plugin = undef;
    for my $available ( $self->expanders ){

        my $klass = undef;
        unless( @EnabledPlugins ){
            $klass = $available;
        }else{
            for my $enable ( @EnabledPlugins ){
                $enable = join('::', $PrefixPlugin, $enable)
                    if( $enable !~ /:/ );
                if( $available eq $enable ){
                    $klass = $available;
                    last;
                }
            }
            next unless( $klass );
        }
        
        load $klass;
        if( $klass->accepts( $type ) ){
            $plugin = $klass->new;
            last;
        }
    }
    return $plugin;
}

sub walk {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $c           = 0;

    my @medias = (Email::MIME->create(
        attributes => {
            content_type    => 'application/octet-stream',
            encoding        => 'binary',
            },
            body => $contents,
        ));

    # flatten contents contains
    while( my $media = shift @medias ){

        my $mime = $self->parsed_mime_type($media->content_type);
        if( ! $mime or $mime =~ m'^application/octet-?stream$' ){ #'
            $mime = $self->guess_content_type($media->body_raw);
            # modify media has content type
            $media->content_type_set($mime);
        }
        my $plugin = $self->plugin_for($mime);
        $self->debug("plugin [@{[ $plugin || '' ]}] for [$mime]");
        if( $self->is_expected_type( $mime ) or ! $plugin ){
            # expected or un-expandable contents
            $callback->($media) if( ref $callback eq 'CODE' );
            ++$c;
        }else{
            # expand more
            $plugin->expand( $media->body, sub {
                my $ref_data = shift;
                my $mime = $self->guess_content_type($$ref_data);
                push @medias, Email::MIME->create(
                    attributes => {
                        content_type => $mime,
                        encoding => 'binary',
                        },
                        body => $$ref_data,
                    );
                });
        }
    }
    
    return $c;
}


1;
__END__

=head1 NAME

MIME::Expander - Expands archived, compressed or multi-parted file by MIME mechanism

=head1 SYNOPSIS

    use MIME::Expander;
    use IO::All;

    my $exp = MIME::Expander->new({
        expects => [
            qr(^application/(:?x-)?zip$),
            ],
        });
    
    my $callback = sub {
            my $em = shift; # Email::MIME object
            print $em->content_type, "\n";
        };
    
    my $num_contents = $exp->walk( io($input)->all, $callback );
    
    print "total $num_contents are expanded.\n";

=head1 DESCRIPTION

MIME::Expander is an utility module that expands archived, compressed or multi-parted file by MIME mechanism.

=head1 CAVEATS

This version only implements in-memory decompression.

=head1 AUTHOR

WATANABE Hiroaki E<lt>hwat@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Email::MIME>

L<File::MMagic>

=cut
