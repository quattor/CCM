#${PMpre} EDG::WP4::CCM::TextRender::Scalar${PMpost}

use Readonly;
use Template::VMethods;

use parent qw(Exporter);

# Overload the stringification
# Following the 'perldoc overload' section on
# 'Magic Autogeneration'; this should be sufficient
# for the other scalar operations numify (via '0+')
# and logic (via 'bool').
# Enable fallback for the case '$obj+1'
# (instead of defining + operator, numify is used as fallback)
# and others like '$obj eq something'.
use overload '""' => '_stringify', 'fallback' => 1;

our @EXPORT_OK =qw(%ELEMENT_TYPES);

Readonly::Hash our %ELEMENT_TYPES => {
    BOOLEAN => 'BOOLEAN',
    STRING => 'STRING',
    DOUBLE => 'DOUBLE',
    LONG => 'LONG',
};

=pod

=head1 NAME

    CCM::TextRender::Scalar - Class to access scalar/property Element attributes within TT.

=head1 DESCRIPTION

This is a wrapper class to access some scalar/property Element attributes
(in particular the type) within TT.

=head2 Methods

=over

=item new

Create a new instance with C<value> and C<type>.

=cut

sub new
{
    my ($class, $value, $type) = @_;

    # TODO if we limit the types, what sort of error checking do we need?
    my $self = {
        VALUE => $value,
        TYPE => $type,
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

=item get_value

Return value (i.e. the VALUE attribute)
(can be useful in case the overloading behaves unexpected)

=cut

sub get_value
{
    my $self = shift;
    return $self->{VALUE};
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
