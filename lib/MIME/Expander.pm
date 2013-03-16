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

sub canonical_content_type {
    return undef unless( defined $_[1] );
    my $data = Email::MIME::ContentType::parse_content_type($_[1]);
    if( $data->{discrete} and $data->{composite} ){
        return join('/',$data->{discrete}, $data->{composite});
    }
    return undef;
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
        guess_type => undef,
        depth   => undef,
        };
    bless $self, $class;
    return $self->init(@_);
}

sub init {
    my $self = shift;
    my $args;
    if( 0 == @_ % 2 ){
        $args = { @_ }
    }else{
        $args = shift || {};
    }

    $self->expects($args->{expects})
        if( exists $args->{expects} );

    $self->guess_type($args->{guess_type})
        if( exists $args->{guess_type} );

    $self->depth($args->{depth})
        if( exists $args->{depth} );

    return $self;
}

sub expects {
    my $self = shift;
    if( @_ ){
        $self->{expects} = shift;
        die "setting value is not acceptable, it requires an reference of ARRAY"
            if( defined $self->{expects} and ref($self->{expects}) ne 'ARRAY' );
    }
    $self->{expects};
}

sub depth {
    my $self = shift;
    return @_ ? $self->{depth} = shift : $self->{depth};
}

sub is_expected {
    my $self = shift;
    my $type = shift or undef;
    for my $regexp ( map { ref $_ ? $_ : qr/^$_$/ } @{$self->expects} ){
        return 1 if( $type =~ $regexp );
    }
    return ();
}

sub guess_type {
    my $self = shift;
    if( @_ ){
        $self->{guess_type} = shift;
        die "setting value is not acceptable, it requires an reference of CODE"
            if( defined $self->{guess_type} and ref($self->{guess_type}) ne 'CODE' );
    }
    $self->{guess_type};
}

sub guess_type_default {
    File::MMagic->new->checktype_contents(${$_[1]});
}

sub guess_type_by_contents {
    my $self     = shift;
    my $ref_data = shift or die "missing mandatory parameter";
    my $meta     = shift || {};
    
    my $type;
    if( ref($self->guess_type) eq 'CODE' ){
        $type = $self->guess_type->($ref_data, $meta);
    }else{
        $type = $self->guess_type_default($ref_data, $meta);
    }
    return ($type || 'application/octet-stream');
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

sub _create_media {
    my $self     = shift;
    my $ref_data = shift or die "missing mandatory parameter";
    my $meta     = shift || {};

    my $type = $self->canonical_content_type($meta->{content_type});
    if( ! $type or $type =~ m'^application/octet-?stream$' ){ #'
        $type = $self->guess_type_by_contents($ref_data, $meta);
    }

    Email::MIME->create(
        attributes => {
            content_type    => $type,
            encoding        => 'binary',
            filename        => $meta->{filename},
            },
        body => $$ref_data,
        );
}

sub walk {
    my $self        = shift;
    my $contents    = shift;
    my $callback    = shift;
    my $meta        = shift || {};
    my $c           = 0;

    my @medias = ($self->_create_media(
        ref $contents eq 'SCALAR' ? $contents : \$contents,
        $meta));

    # flatten contents contains
    my $ptr     = 0;
    my $limit   = 0;
    my $level   = 1;
    my $bound   = scalar @medias;
    $self->debug("initial bound=[$bound]");
    while( my $media = shift @medias ){
        $self->debug("====> shift media, remains=[@{[ scalar @medias ]}]");

        my $type    = $media->content_type;
        my $plugin  = $self->plugin_for($type);
        $self->debug("* type is [$type], plugin_for [@{[ $plugin || '' ]}]");

        if( $limit or $self->is_expected( $type ) or ! $plugin ){
            # expected or un-expandable contents
            $self->debug("=> limited, expected or un-expandable contents");
            $callback->($media) if( ref $callback eq 'CODE' );
            ++$c;
        }else{
            # expand more
            $self->debug("==> expand more");
            # note: undocumented api is used ->{body}
            $plugin->expand( $media->{body} , sub {
                push @medias, $self->_create_media( @_ );
            });
        }

        ++$ptr;
        $self->debug("increment ptr=[$ptr] | bound=[$bound] level=[$level]");
        if( $bound <= $ptr ){
            
            if( $self->depth and $self->depth <= $level ){
                $limit = 1;
                $self->debug("set limit to TRUE");
            }
            $bound += scalar @medias;
            $self->debug("update bound=[$bound]");
            ++$level;
            $self->debug("update level=[$level]");
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
            my $type = $em->content_type;
            if( $exp->is_expected( $type ) ){
                print "$type is expected\n";
            }
        };
    
    my $num_contents = $exp->walk( io($input)->all, $callback );
    
    print "total $num_contents are expanded.\n";

=head1 DESCRIPTION

MIME::Expander is an utility module that expands archived, compressed or multi-parted file by MIME mechanism.

=head1 CONSTRUCTOR

The constructor new() creates an instance, and accepts a reference of hash as configurations.

=head1 CLASS METHODS

=head2 canonical_content_type( $content_type )

TODO

=head1 INSTANCE METHODS

=head2 init

TODO

=head2 expects( \@list )

TODO

=head2 is_expected( $type )

TODO

=head2 guess_type( \&code )

TODO

=head2 guess_type_default( \$contents )

TODO

=head2 guess_type_by_contents( \$contents, \%meta )

TODO

=head2 plugin_for( $type )

TODO

=head2 walk( $contents, $callback )

TODO

=head1 IMPORT

TODO

=head1 PLUGIN

TODO - See also L<MIME::Expander::Plugin>

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
