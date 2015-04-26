# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::TextRender;

use strict;
use warnings;
use CAF::TextRender qw($YAML_BOOL_PREFIX);
use Readonly;
use EDG::WP4::CCM::TT::Scalar qw(%ELEMENT_TYPES);
use base qw(CAF::TextRender Exporter);

our @EXPORT_OK = qw(%ELEMENT_CONVERT);

Readonly::Hash our %ELEMENT_CONVERT => {
    'json_boolean' => sub {
        my $value = shift;
        return $value ? \1 : \0;
    },
    'yaml_boolean' => sub {
        my $value = shift;
        #return $value ? $YAML_BOOL->{yes} : $YAML_BOOL->{no};
        return $YAML_BOOL_PREFIX .
            ($value ? 'true' : 'false');
    },
    'yesno_boolean' => sub {
        my $value = shift;
        return $value ? 'yes' : 'no';
    },
    'upper' => sub {
        my $value = shift;
        return uc $value;
    },
    'doublequote_string' => sub {
        my $value = shift;
        return "\"$value\"";
    },
    'singlequote_string' => sub {
        my $value = shift;
        return "'$value'";
    },
};


=pod

=head1 NAME

    CCM::TextRender - Class for rendering structured text using Element instances

=head1 DESCRIPTION

This class is an extension of the C<CAF::TextRender> class; with the main
difference the support of a C<EDG::WP4::CCM:Element> instance as contents.

=head2 Private methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item module

The rendering module to use (see C<CAF::TextRender> for details).

=item contents

C<contents> is either a hash reference holding the contents to pass to the rendering module;
or a C<EDG::WP4::CCM:Element> instance, on which C<getTree> is called with any C<element>
options.

=back

All optinal arguments from C<CAF::TextRender> are supported unmodified:

=over

=item log

=item includepath

=item relpath

=item eol

=item usecache

=item ttoptions

=back

Extra optional arguments:

=over

=item element

A hashref holding any C<getTree> options to pass. These can be the
anonymous convert methods C<convert_boolean>, C<convert_string>,
C<convert_long> and C<convert_double>; or one of the
predefined convert methods (key is the name, value a boolean
wheter or not to use them). The C<convert_> methods take precedence over
the predefined ones in case there is any overlap.

The predefined convert methods are:

=over

=item json

Enable JSON output, in particular JSON boolean (the other types should
already be in proper format). This is automatically enabled when the json
module is used (and not explicilty set).

=item yaml

Enable YAML output, in particular YAML boolean (the other types should
already be in proper format). This is automatically enabled when the yaml
module is used (and not explicilty set).

=item yesno

Convert boolean to (lowercase) 'yes' and 'no'.

=item YESNO

Convert boolean to (uppercase) 'YES' and 'NO'.

=item doublequote

Convert string to doublequoted string.

=item singlequote

Convert string to singlequoted string.

=back

Other C<getTree> options

=over

=item depth

Only return the next C<depth> levels of nesting (and use the
Element instances as values). A C<depth == 0> is the element itself,
C<depth == 1> is the first level, ...

Default or depth C<undef> returns all levels.

=back

=back

=cut

sub _initialize
{
    my ($self, $module, $contents, %opts) = @_;

    if (defined($opts{element})) {
        # Make a (modifiable) copy
        $self->{elementopts} = { %{$opts{element}} };
        delete $opts{element};
    } else {
        $self->{elementopts} = {};
    }

    return $self->SUPER::_initialize($module, $contents, %opts);
}

# Return the validated contents. Either the contents are a hashref
# (in that case they are left untouched) or a C<EDG::WP4::CCM::Element> instance
# in which case C<getTree> is called together with the relevant C<elementopts>
sub make_contents
{
    my ($self) = @_;

    my $contents;

    my $ref = ref($self->{contents});

    if($ref && ($ref eq "HASH")) {
        $contents = $self->{contents};
    } elsif ($ref && UNIVERSAL::can($self->{contents},'can') &&
             $self->{contents}->isa('EDG::WP4::CCM::Element')) {
        # Test for a blessed reference with UNIVERSAL::can
        # UNIVERSAL::can also return true for scalars, so also test
        # if it's a reference to start with
        $self->debug(3, "Contents is a Element instance");
        my $elopts = $self->{elementopts};
        my $depth = $elopts->{depth};

        if ($self->{module} && $self->{module} eq 'json' &&
            ! defined( $elopts->{json})) {
            $elopts->{json} = 1;
        } elsif ($self->{module} && $self->{module} eq 'yaml' &&
            ! defined( $elopts->{yaml})) {
            $elopts->{yaml} = 1;
        }

        my %opts;

        # predefined convert_
        if ($elopts->{json}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{json_boolean});
        } elsif ($elopts->{yaml}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{yaml_boolean});
        }

        if ($elopts->{yesno} || $elopts->{YESNO}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{yesno_boolean});
        }

        if ($elopts->{YESNO}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{upper});
        }

        if ($elopts->{doublequote}) {
            push(@{$opts{convert_string}}, $ELEMENT_CONVERT{doublequote_string});
        } elsif ($elopts->{singlequote}) {
            push(@{$opts{convert_string}}, $ELEMENT_CONVERT{singlequote_string});
        }

        # The convert_ anonymous methods precede the predefined ones
        foreach my $type (qw(boolean string long double)) {
            my $am_name = "convert_$type";
            my $am = $elopts->{$am_name};
            # Convert to arrayrefs
            if (defined ($am)) {
                if (ref($am) ne 'ARRAY') {
                    push(@{$opts{$am_name}}, $am);
                } else {
                    push(@{$opts{$am_name}}, @$am);
                }
            }
        }

        # Last step: add convert methods for scalar types to CCM::TT::Scalar
        # if the render method is TT
        if ($self->{method_is_tt}) {
            foreach my $type (qw(boolean string long double)) {
                push(@{$opts{"convert_$type"}}, sub {
                    my $scalartype = $ELEMENT_TYPES{(uc $type)};
                    return EDG::WP4::CCM::TT::Scalar->new($_[0], $scalartype);
                     });
            }
        }

        $contents = $self->{contents}->getTree($depth, %opts);

    } else {
        return $self->fail("Contents passed is neither a hashref or ",
                           "a EDG::WP4::CCM::Element instance ",
                           "(ref ", ref($self->{contents}), ")");
    }


    # Additional variables available to both regular hashref and element
    my $extra_vars = {
        # Make the full contents available (e.g. to access the root keys)
        # Must be a copy
        contents => { %$contents },
        ref => sub { return ref($_[0]) },
        is_scalar => sub { my $r = ref($_[0]); return (! $r || $r eq 'EDG::WP4::CCM::TT::Scalar');  },
        is_list => sub { my $r = ref($_[0]); return ($r && ($r eq 'ARRAY'));  },
        is_hash => sub { my $r = ref($_[0]); return ($r && ($r eq 'HASH'));  },
    };

    while (my ($k, $v) = each %$extra_vars) {
        $self->{ttoptions}->{VARIABLES}->{CCM}->{$k} = $v;
    }

    return $contents;
}

=pod

=back

=cut

1;
