# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::Format;

use strict;
use warnings;

use parent qw(CAF::Object Exporter);
use EDG::WP4::CCM::TextRender;

use overload '""' => "_stringify";

use LC::Exception qw (SUCCESS);

use Readonly;

Readonly::Array my @FORMATS_OTHER => ();

Readonly::Hash my %FORMATS_TEXTRENDER => {
    json => {}, # No opts
    yaml => {}, # No opts
    pan => { truefalse => 1},
};

my @FORMATS = keys %FORMATS_TEXTRENDER;
push(@FORMATS, @FORMATS_OTHER);

our @EXPORT_OK = qw(@FORMATS);

=head1 NAME

EDG::WP4::CCM::Format - CCM Format class

=head1 DESCRIPTION

Module provides the Format class, to generate a text
representation of an element.

The module supports stringification as a method to
retrieve the generated text.

=over

=item new

Create a C<EDG::WP4::CCM::Format> instance
with format C<format> from C<element> .

Supported options are

=over

=item log

A logger instance (compatible with C<CAF::Object>).

=back

=cut

sub _initialize
{
    my ($self, $format, $element, %opts) = @_;

    $self->{element} = $element;
    $self->{format} = $format;

    # The actual text
    $self->{text} = undef;

    $self->{log} = $opts{log} if $opts{log};

    return SUCCESS;
}

=pod

=item get_text

Generate the text by selecting the correct format method.

Returns undef on failure.

=cut

sub get_text
{
    my ($self) = @_;

    # Reset the actual text
    $self->{text} = undef;

    my $trd_opts = $FORMATS_TEXTRENDER{$self->{format}};
    if (defined($trd_opts)) {
        $trd_opts->{depth} = $self->{depth} if defined $self->{depth};
        # Format is the TextRender module
        my $trd = EDG::WP4::CCM::TextRender->new(
            $self->{format},
            $self->{element},
            # uppercase, no conflict with possible ncm-ccm?
            relpath => 'CCM',
            element => $trd_opts,
            );
        if (defined $trd->get_text()) {
            $self->{text} = "$trd";
        } else {
            $self->error("Failed to textrender format $self->{format}: $trd->{fail}");
        }
    } elsif (grep {$_ eq $self->{format}} @FORMATS_OTHER) {
        $self->error("Unimplemented format $self->{format}");
    } else {
        $self->error("Unsupported format $self->{format}");
    }

    return $self->{text};
}


sub _stringify
{
    my $self = shift;

    # Either first run or failure
    if(! defined($self->{text})) {
        $self->get_text();
    }

    # Always return a string for stringification
    return defined($self->{text}) ? $self->{text} : '';
}

=pod

=back

=cut

1;
