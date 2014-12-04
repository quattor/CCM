# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::Property;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use LC::File qw (file_contents);
use parent qw(EDG::WP4::CCM::Element);

my $ec = LC::Exception::Context->new->will_store_errors;

=head1 NAME

EDG::WP4::CCM::Property - Property class

=head1 SYNOPSIS

 $string = $property->getStringValue();
 $double = $property->getDoubleValue();
 $long = $property->getLongValue();
 $boolean = $property->getBooleanValue();

=head1 DESCRIPTION

The class Property is a derived class of Element class, and implements
methods that are specific to Properties, that is, simple values
like strings or numbers that form the leaves of the configuration
tree.

=over

=cut

#
#=item new($config, $prop_path)
#
#Create new Property object. The $config parameter is a Configuration
#object with the profile. The $prop_path parameter is the property's
#configuration path.
#
#=cut
#

sub new {

    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(@_);

    # check that element it is a property
    if ( !$self->isProperty() ) {
        throw_error("element is not of type property");
        return ();
    }

    bless( $self, $class );
    return ($self);

}

=item getStringValue()

Return the property's string value,
raising an exception if the value is not an string or fetch

=cut

sub getStringValue {

    my $self = shift;

    if ( $self->isType( $self->STRING ) ) {
        return ( $self->{VALUE} );
    }
    throw_error("property is not of type STRING");
    return ();
}

=item getDoubleValue()

Return the property's double value,
raising an exception if the value is not a double

=cut

sub getDoubleValue {

    my $self = shift;

    # check that resource is of type double
    if ( !$self->isType( $self->DOUBLE ) ) {
        throw_error("property is not of type DOUBLE");
        return ();
    }

    return ( $self->{VALUE} );

}

=item getLongValue()

Return the property's long value,
raising an exception if the value is not a long

=cut

sub getLongValue {

    my $self = shift;

    # check that resource is of type long
    if ( !$self->isType( $self->LONG ) ) {
        throw_error("property is not of type LONG");
        return ();
    }

    return ( $self->{VALUE} );

}

=item getBooleanValue()

Return the property's boolean value,
raising an exception if the value is not a boolean

=cut

sub getBooleanValue {

    my $self = shift;
    # check that resource is of type boolean
    if ( !$self->isType( $self->BOOLEAN ) ) {
        throw_error("property is not of type BOOLEAN");
        return ();
    }

    return ( $self->{VALUE} );

}

=pod

=back

=cut

1;
