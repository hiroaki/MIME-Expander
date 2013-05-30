package MIME::Expander;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '0.01';

use vars qw($DEBUG);
$DEBUG = 0;

use vars qw($PrefixGuess $PrefixPlugin @DefaultGuesser @EnabledPlugins);
BEGIN {
    $PrefixGuess    = 'MIME::Expander::Guess';
    $PrefixPlugin   = 'MIME::Expander::Plugin';
    @DefaultGuesser = ('MMagic', 'FileName');
    @EnabledPlugins = ();
}

use Email::MIME;
use Email::MIME::ContentType ();
use MIME::Type;
use Module::Load;
use Module::Pluggable search_path => $PrefixPlugin, sub_name => 'expanders';

sub import {
    my $class = shift;
    @EnabledPlugins = @_;
}

sub regulate_type {
    return undef unless( defined $_[1] );
    my $type = $_[1];

    # There is regexp from Email::MIME::ContentType 1.015
    my $tspecials = quotemeta '()<>@,;:\\"/[]?=';
    my $discrete  = qr/[^$tspecials]+/;
    my $composite = qr/[^$tspecials]+/;
    my $params    = qr/;.*/;
    return undef unless( $type =~ m[ ^ ($discrete) / ($composite) \s* ($params)? $ ]x );

    my $ct = Email::MIME::ContentType::parse_content_type($type);
    return undef if( ! $ct->{discrete} or ! $ct->{composite} );
    return MIME::Type->simplified(join('/',$ct->{discrete}, $ct->{composite}));
}

sub debug {
    my $self = shift;
    my $msg = shift or return;
    printf STDERR "# %s: %s\n", $self, $msg if( $DEBUG );
}

sub new {
    my $class = shift;
    $class = ref $class || $class;
    my $self = {
        expects     => [],
        guesser     => undef,
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

    $self->expects(
        exists $args->{expects} ? $args->{expects} : [] );

    $self->guesser(
        exists $args->{guesser} ? $args->{guesser} : undef );

    $self->depth(
        exists $args->{depth} ? $args->{depth} : undef );

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
    die "invalid type $type that has not looks as mime/type"
        if( $type !~ m,^.+/.+$, );
    return () unless( $self->expects );
    for my $regexp ( map { ref $_ ? $_ : qr/$_/ } @{$self->expects} ){
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

sub guesser {
    my $self = shift;
    if( @_ ){
        $self->{guesser} = shift;
        die "setting value is not acceptable, it requires an reference of CODE or ARRAY"
            if( defined $self->{guesser} 
            and ref($self->{guesser}) ne 'CODE'
            and ref($self->{guesser}) ne 'ARRAY');
    }
    return $self->{guesser};
}

sub guess_type_of {
    my $self     = shift;
    my $ref_data = shift or die "missing mandatory parameter";
    my $info     = shift || {};
    
    my $type    = undef;
    my $routine = $self->guesser;

    if(     ref $routine eq 'CODE' ){
        $type = $self->guesser->($ref_data, $info);

    }else{
        my @routines;
        if( ref $routine eq 'ARRAY' ){
            @routines = @$routine;
        }else{
            @routines = @DefaultGuesser;
        }
        for my $klass ( @routines ){
            $klass = join('::', $PrefixGuess, $klass) if( $klass !~ /:/ );
            Module::Load::load $klass;
            $type = $self->regulate_type( $klass->type($ref_data, $info) );
            last if( $type and $type ne 'application/octet-stream');
        }
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
        if( $klass->is_acceptable( $type ) ){
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

    my $type = $self->regulate_type($info->{content_type});
    if( ! $type or $type eq 'application/octet-stream' ){
        $type = $self->guess_type_of($ref_data, $info);
    }

    return Email::MIME->create(
        attributes => {
            content_type    => $type,
            encoding        => 'binary',
            filename        => $info->{filename},
            },
        body => $ref_data,
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

    my $callback = sub {
            my $em = shift; # is an Email::MIME object
            $em->body_raw > io( $em->filename );
        };
    
    my $exp = MIME::Expander->new;    
    my $num_contents = $exp->walk( io($ARGV[0])->all, $callback );
    
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

=item guesser

A value is a reference of code or reference of array which contains name of the "guess classes".
In the case of a code, it is only performed for determining the mime type.
In array, it performs in order of the element, and what was determined first is adopted.

Each routines have to determine the type of the data which will be inputted.

The parameters passed to a routine are a reference of scalar to contents, 
and information as reference of hash.

Although the information may have a "filename",
however depending on implements of each expander module, it may not be expectable.

The routine have to return mime type string, or undef.
If value of return is false value, that means "application/octet-stream".

For example, sets routine which determine text or jpeg.

    my $exp = MIME::Expander->new({
        guesser => sub {
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

When useing the "guess classes", like this is the default of guesser, package name is omissible:

    my $exp = MIME::Expander->new({
        guesser => [qw/MMagic FileName/],
        });

Please look in under namespace of L<MIME::Expander::Guess> about what kinds of routine are available.

=item depth

A value is a native number.

Please see "walk".

=back

=head1 CLASS METHODS

=head2 regulate_type( $type )

Simplify when the type which removed "x-" is registered.

    MIME::Expander->regulate_type("text/plain; charset=ISO-2022-JP");
    #=> "text/plain"

    MIME::Expander->regulate_type('application/x-tar');
    #=> "application/tar"

Please see about "simplified" in the document of L<MIME::Type>.

=head1 INSTANCE METHODS

=head2 init

Initialize instance. This is for overriding.

=head2 expects( \@list )

Accessor to field "expects".

=head2 is_expected( $type )

Is $type the contents set to field "expects" ?

=head2 depth( $native_number )

Accessor to field "depth".

=head2 guesser( \&code | \@list )

Accessor to field "guesser".

=head2 guess_type_of( \$contents, [\%info] )

Determine mime type from the $contents.

Optional %info is as hint for determing mime type.
It will be passed to "guesser" directly.

A key "filename" can be included in %info.

=head2 plugin_for( $type )

Please see the PLUGIN section.

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

    $me->walk( \$data, sub {
            my $email = shift;
            my $name  = $email->filename;
            open my $fh, ">$name" or die;
            $fh->print($email->body_raw);
            close $fh;
        });

See also L<Email::MIME> about $email object.

Only this $email object has rules on this MIME::Expander utility class.
The expanded data is set to "body" and the Content-Transfer-Encoding is "binary".
Therefore, in order to take out the expanded contents, please use "body_raw" method.

=head1 PLUGIN

Expanding module for expand contents can be added as plug-in. 

Please see L<MIME::Expander::Plugin> for details.

=head1 CAVEATS

This version only implements in-memory decompression.

=head1 AUTHOR

WATANABE Hiroaki E<lt>hwat@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Email::MIME>

=cut
