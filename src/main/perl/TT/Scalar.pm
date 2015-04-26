# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::TT::Scalar;

use strict;
use warnings;

use Readonly;
use Template::VMethods;

use base qw(Exporter);

use overload ('""' => '_stringify');

our @EXPORT_OK =qw(%ELEMENT_TYPES);

Readonly::Hash our %ELEMENT_TYPES => {
    BOOLEAN => 'BOOLEAN',
    STRING => 'STRING',
    DOUBLE => 'DOUBLE',
    LONG => 'LONG',
};

=pod

=head1 NAME

    CCM::TT::Scalar - Class to expose scalar/property Element attributes within TT.

=head1 DESCRIPTION

This is a wrapper class to access some scalar/property Element properties (in particular
the type) available within TT.

=head2 Methods

=over

=item new

Create a new instance with C<value> and C<type>

=cut

sub new
{
    my ($class, $value, $type) = @_;

    # TODO if we limit the types, what sort of error checking do we need?
    my $self = {
        VALUE => $value,
        TYPE => uc $type,
    };
    bless $self, $class;

    return $self;
}

=pod

=item _stringify

Method called to stringification. Simply returns the data in string context

=cut

sub _stringify
{
    my ($self) = @_;
    return "$self->{VALUE}";
}

=pod

=item get_type

Return TYPE attribute

=cut

sub get_type
{
    my $self = shift;
    return $self->{TYPE};
}

=pod

=item is_boolean

Return true if the TYPE is boolean

=cut

sub is_boolean
{
    my $self = shift;
    return $self->{TYPE} eq $ELEMENT_TYPES{BOOLEAN};
}

=pod

=item is_string

Return true if the TYPE is string

=cut

sub is_string
{
    my $self = shift;
    return $self->{TYPE} eq $ELEMENT_TYPES{STRING};
}

=pod

=item is_double

Return true if the TYPE is double

=cut

sub is_double
{
    my $self = shift;
    return $self->{TYPE} eq $ELEMENT_TYPES{DOUBLE};
}

=pod

=item is_long

Return true if the TYPE is long

=cut

sub is_long
{
    my $self = shift;
    return $self->{TYPE} eq $ELEMENT_TYPES{LONG};
}

# Generate all regular TT scalar methods
# from $Template::VMethods::TEXT_VMETHODS
no strict 'refs';
while (my ($name, $method) = each %{$Template::VMethods::TEXT_VMETHODS}) {
    *{$name} = sub {
        my ($self, @args) = @_;
        return $method->($self->{VALUE}, @args);
    }
}
use strict 'refs';

=pod

=back

=cut

1;
