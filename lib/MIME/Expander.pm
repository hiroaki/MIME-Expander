package MIME::Expander;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use vars qw($DEBUG);
$DEBUG = 0;

use Email::MIME;
use Email::MIME::ContentType ();
use Module::Load;
use Module::Pluggable sub_name => 'expanders';

my $PrefixPlugin   = 'MIME::Expander::Plugin';
my @EnabledPlugins = ();

sub import {
    my $class = shift;
    @EnabledPlugins = @_;
}

sub canonical_content_type {
    return undef unless( defined $_[1] );
    my $ct = Email::MIME::ContentType::parse_content_type($_[1]);
    if( $ct->{discrete} and $ct->{composite} ){
        return join('/',$ct->{discrete}, $ct->{composite});
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
        expects     => [],
        guess_type  => undef,
        depth       => undef,
        };
    bless  $self, $class;
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
    return $self->{expects};
}

sub is_expected {
    my $self = shift;
    my $type = shift or undef;
    for my $regexp ( map { ref $_ ? $_ : qr/^$_$/ } @{$self->expects} ){
        return 1 if( $type =~ $regexp );
    }
    return ();
}

sub depth {
    my $self = shift;
    if( @_ ){
        $self->{depth} = shift;
        die "setting value is not acceptable, it requires a native number"
            if( defined $self->{depth} and $self->{depth} =~ /\D/ );
    }
    return $self->{depth};
}

sub guess_type {
    my $self = shift;
    if( @_ ){
        $self->{guess_type} = shift;
        die "setting value is not acceptable, it requires an reference of CODE"
            if( defined $self->{guess_type} and ref($self->{guess_type}) ne 'CODE' );
    }
    return $self->{guess_type};
}

sub guess_type_default {
    Module::Load::load File::MMagic;
    return File::MMagic->new->checktype_contents(${$_[1]});
}

sub guess_type_by_contents {
    my $self     = shift;
    my $ref_data = shift or die "missing mandatory parameter";
    my $info     = shift || {};
    
    my $type;
    if( ref($self->guess_type) eq 'CODE' ){
        $type = $self->guess_type->($ref_data, $info);
    }else{
        $type = $self->guess_type_default($ref_data, $info);
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
        
        Module::Load::load $klass;
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
    my $info     = shift || {};

    my $type = $self->canonical_content_type($info->{content_type});
    if( ! $type or $type =~ m'^application/octet-?stream$' ){ #'
        $type = $self->guess_type_by_contents($ref_data, $info);
    }

    return Email::MIME->create(
        attributes => {
            content_type    => $type,
            encoding        => 'binary',
            filename        => $info->{filename},
            },
        body => $$ref_data,
        );
}

sub walk {
    my $self        = shift;
    my $data        = shift;
    my $callback    = shift;
    my $info        = shift || {};
    my $c           = 0;

    my @medias = ($self->_create_media(
        ref $data eq 'SCALAR' ? $data : \$data,
        $info));

    # reset vars for depth option
    my $ptr     = 0;
    my $limit   = 0;
    my $level   = 1;
    my $bound   = scalar @medias;
    
    # when expandable contents, then append it to @medias
    while( my $media = shift @medias ){
        $self->debug("====> shift media, remains=[@{[ scalar @medias ]}]");

        my $type    = $media->content_type;
        my $plugin  = $self->plugin_for($type);
        $self->debug("* type is [$type], plugin_for [@{[ $plugin || '' ]}]");

        if( $limit or $self->is_expected( $type ) or ! $plugin ){
            # expected or un-expandable data
            $self->debug("=> limited, expected or un-expandable data");
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
        $self->debug("incremented ptr=[$ptr] | bound=[$bound] level=[$level]");
        if( $bound <= $ptr ){
            
            if( $self->depth and $self->depth <= $level ){
                $limit = 1;
                $self->debug("set limit to TRUE");
            }
            $bound += scalar @medias;
            ++$level;
            $self->debug("updated bound=[$bound] level=[$level]");
        }
    }
    
    return $c;
}


1;
__END__


=pod

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

=head1 CONSTRUCTOR AND ACCESSORS

The constructor new() creates an instance, and accepts a reference of hash as configurations.

Following key of hash are available, and there is an access method of a same name.

=over 4

=item expects

A value is a list reference and the elements are string or regular expression.

If this parameter is set, then the walk() will not expand contents of specified mime types.

=item guess_type

A value is a code reference.

The routine have to determine the type of the data which will be inputted.

The parameters passed to the routine are a reference of scalar to contents, 
and information as reference of hash. 

Although the information may have a "filename",
however depending on implements of each expander module, it may not be expectable.

The routine have to return mime type string, or undef.
If value of return is false value, that means "application/octet-stream".

For example, sets routine which determine text or jpeg.

    my $exp = MIME::Expander->new({
        guess_type => sub {
                my $ref_contents = shift;
                my $info         = shift || {};
                if( defined $info->{filename} ){
                    my ($suffix) = $info->{filename} =~ /\.(.+)$/;
                    if( defined $suffix ){
                        if( lc $suffix eq 'txt' ){
                            return 'text/plain';
                        }elsif( $suffix =~ /^jpe?g$/i ){
                            return 'image/jpeg';
                        }
                    }
                }
            },
        });

There is default routine that will call guess_type_default() method.

=item depth

A value is a native number.

Please see "walk".

=back

=head1 CLASS METHODS

=head2 canonical_content_type( $content_type )

This is an utility for unifying header "Content-type" with parameters.

    MIME::Expander->canonical_content_type(
        "text/plain; charset=ISO-2022-JP");
    #=> "text/plain"

=head1 INSTANCE METHODS

=head2 init

Initialize instance. This is for override.

=head2 expects( \@list )

Accessor to field "expects".

=head2 is_expected( $type )

Is $type the contents set to field "expects" ?

=head2 depth( $native_number )

Accessor to field "depth".

=head2 guess_type( \&code )

Accessor to field "guess_type".

=head2 guess_type_default( \$contents )

It is called when the field "guess_type" is not set.

=head2 guess_type_by_contents( \$contents, \%info )

The routine "guess_type" actually determines mime type.

Optional %info is as hint for determing mime type.
It will be passed to a "guess_type" routine directly.

"filename" can be included in %info.

=head2 plugin_for( $type )

TODO

=head2 walk( \$data, $callback )

If the $data which can be expanded in the inputted data exists,
it will be expanded and passed to callback.

The expanded data are further checked and processed recursively.

The recursive depth is to the level of the value of "depth" field.

A media object which is a L<Email::MIME>, is passed to the callback routine, 
They are the results of this module. 

As the work, it sometimes often saves.
However the file name may not be obtained with the specification of expander module.
But it may be used, since it is set to "filename" attribute when it exists.

    $me->expand( \$data, sub {
            my $email = shift;
            my $name  = $email->invent_filename;
            open my $fh, ">$name" or die;
            $fh->print($email->body_raw);
            close $fh;
        });

See also L<Email::MIME> for $email object.

Only this $email object has rules on this MIME::Expander utility class.
The expanded data is set to "body" and the Content-Transfer-Encoding is "binary".
Therefore, in order to take out the expanded contents, please use "body_raw" method.

=head1 IMPORT

TODO

=head1 PLUGIN

TODO - See also L<MIME::Expander::Plugin>.

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
