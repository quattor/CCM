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
use EDG::WP4::CCM::Element qw(escape unescape);
use XML::Parser;
use base qw(CAF::TextRender Exporter);

our @EXPORT_OK = qw(%ELEMENT_CONVERT @CCM_FORMATS ccm_format);

# private instance for xml_string processing
my $_xml_parser = XML::Parser->new(Style => 'Tree');

# test if C<txt> is valid xml by trying to parse it with XML::Parser
sub _is_valid_xml
{
    my $txt = shift;

    # XML::Parser->parse uses 'die' with invalid xml.
    my $tag = "really_really_random_tag";

    my $t = eval {$_xml_parser->parse("<$tag>$txt</$tag>");};
    return $@ ? 0 : 1;
}

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
    'truefalse_boolean' => sub {
        my $value = shift;
        return $value ? 'true' : 'false';
    },
    'upper' => sub {
        my $value = shift;
        return uc $value;
    },
    'lower' => sub {
        my $value = shift;
        return lc $value;
    },
    'doublequote_string' => sub {
        my $value = shift;
        return "\"$value\"";
    },
    'singlequote_string' => sub {
        my $value = shift;
        return "'$value'";
    },
    'cast_boolean' => sub {
        my $value = shift;
        # Closest to a perl internal true/false
        return $value ? (0 == 0) : (0 == 1);
    },
    'cast_string' => sub {
        my $value = shift;
        # explicit stringification
        return "$value";
    },
    'cast_long' => sub {
        my $value = shift;
        # the 0+ operator of value is used
        return 0 + $value;
    },
    'cast_double' => sub {
        my $value = shift;
        # the 0+ operator of value is used
        return 0.0 + $value;
    },
    'xml_primitive_string' => sub {
        # Ideally, this is done with some CPAN module,
        # but would introduce (non-standard) dependencies

        my $value = shift;
        return $value if _is_valid_xml($value);

        # wrap it in CDATA, see http://stackoverflow.com/a/5337851
        my $text = $value;
        # use global flag for repeated replacements
        $text =~ s/\]\]>/]]>]]&gt;<![CDATA[/g;
        $text = "<![CDATA[$text]]>";
        return $text if _is_valid_xml($text);

        # ?
        die("xml_primitive_string: Unable to create valid xml from '$value'");
    },
};

# Update the ccm_format pod with new formats
Readonly::Hash my %TEXTRENDER_FORMATS => {
    json => {}, # No opts
    yaml => {}, # No opts
    pan => { truefalse => 1, doublequote => 1},
    pancxml => { truefalse => 1, xml => 1 },
};

Readonly::Array our @CCM_FORMATS => sort keys %TEXTRENDER_FORMATS;;

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

All optional arguments from C<CAF::TextRender> are supported unmodified:

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
wheter or not to use them).

The C<convert_> methods are added as last methods.

The predefined convert methods are:

=over

=item cast

Convert the scalar values to a more exact internal representation.
The internal representaiton is important when passed on to other
non-pure perl code, in particular the C<XS> modules like C<JSON::XS>
and C<YAML::XS>.

=item json

Enable JSON output, in particular JSON boolean (C<cast> is implied,
so the other types should already be in proper format).
This is automatically enabled when the json
module is used (and not explicitly set).

=item yaml

Enable YAML output, in particular YAML boolean (C<cast> is implied,
so the other types should already be in proper format).
This is automatically enabled when the yaml
module is used (and not explicitly set).

=item yesno

Convert boolean to (lowercase) 'yes' and 'no'.

=item YESNO

Convert boolean to (uppercase) 'YES' and 'NO'.

=item truefalse

Convert boolean to (lowercase) 'true' and 'false'.

=item TRUEFALSE

Convert boolean to (uppercase) 'TRUE' and 'FALSE'.

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

# Modify the elementopts attribute based on selected module
sub _modify_elementopts_module
{
    my ($self) = @_;

    my $elopts = $self->{elementopts};
    if ($self->{module} && $self->{module} eq 'json' &&
        ! defined( $elopts->{json})) {
        $elopts->{json} = 1;
    } elsif ($self->{module} && $self->{module} eq 'yaml' &&
             ! defined( $elopts->{yaml})) {
        $elopts->{yaml} = 1;
    }
}

# Returns the hash with getTree options generated
# from the predefined convert options
sub _make_predefined_options
{
    my ($self) = @_;

    my $elopts = $self->{elementopts};
    my %opts;

    if ($elopts->{cast} || $elopts->{json} || $elopts->{yaml}) {
        push(@{$opts{convert_string}}, $ELEMENT_CONVERT{cast_string});
        push(@{$opts{convert_long}}, $ELEMENT_CONVERT{cast_long});
        push(@{$opts{convert_double}}, $ELEMENT_CONVERT{cast_double});

        # Booleans already converted to 0 or 1
        # For JSON and YAML, the casted booleans are not in the correct
        # internal format
        my $bool_conv = $ELEMENT_CONVERT{cast_boolean};
        if ($elopts->{json}) {
            $bool_conv = $ELEMENT_CONVERT{json_boolean};
        } elsif ($elopts->{yaml}) {
            $bool_conv = $ELEMENT_CONVERT{yaml_boolean};
        }

        push(@{$opts{convert_boolean}}, $bool_conv);
    }

    if ($elopts->{xml}) {
        push(@{$opts{convert_string}}, $ELEMENT_CONVERT{xml_primitive_string});
    }

    if ($elopts->{yesno} || $elopts->{YESNO}) {
        push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{yesno_boolean});
        if ($elopts->{YESNO}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{upper});
        }
    } elsif ($elopts->{truefalse} || $elopts->{TRUEFALSE}) {
        push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{truefalse_boolean});
        if ($elopts->{TRUEFALSE}) {
            push(@{$opts{convert_boolean}}, $ELEMENT_CONVERT{upper});
        }
    }


    if ($elopts->{doublequote}) {
        push(@{$opts{convert_string}}, $ELEMENT_CONVERT{doublequote_string});
    } elsif ($elopts->{singlequote}) {
        push(@{$opts{convert_string}}, $ELEMENT_CONVERT{singlequote_string});
    }

    return %opts;
}

# Return the validated contents. Either the contents are a hashref
# (in that case they are left untouched) or a C<EDG::WP4::CCM::Element> instance
# in which case C<getTree> is called together with the relevant C<elementopts>
sub make_contents
{
    my ($self) = @_;

    my $contents;

    my $ref = ref($self->{contents});

    # Additional variables available to both regular hashref and element
    my $extra_vars = {
        ref => sub { return ref($_[0]) },
        is_scalar => sub { my $r = ref($_[0]); return (! $r || $r eq 'EDG::WP4::CCM::TT::Scalar');  },
        is_list => sub { my $r = ref($_[0]); return ($r && ($r eq 'ARRAY'));  },
        is_hash => sub { my $r = ref($_[0]); return ($r && ($r eq 'HASH'));  },
        escape => \&escape,
        unescape => \&unescape,
    };


    if($ref && ($ref eq "HASH")) {
        $contents = $self->{contents};
    } elsif ($ref && UNIVERSAL::can($self->{contents}, 'can') &&
             $self->{contents}->isa('EDG::WP4::CCM::Element')) {
        # Test for a blessed reference with UNIVERSAL::can
        # UNIVERSAL::can also return true for scalars, so also test
        # if it's a reference to start with

        $self->debug(3, "Contents is a Element instance");
        my $elopts = $self->{elementopts};
        my $depth = $elopts->{depth};

        $self->_modify_elementopts_module();

        my %opts = $self->_make_predefined_options();

        # The convert_ anonymous methods are added last
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

        # Add the path as an arrayref that can be joined to the correct path
        $extra_vars->{element} = {
            path => $self->{contents}->getPath(),
        }

    } else {
        return $self->fail("Contents passed is neither a hashref or ",
                           "a EDG::WP4::CCM::Element instance ",
                           "(ref ", ref($self->{contents}), ")");
    }



    # Make the full contents available (e.g. to access the root keys)
    # Must be a copy
    $extra_vars->{contents} = { %$contents };

    # Add extra_vars to the CCM namespace
    # To be used in TT as follows: [% CCM.is_hash(myvar) ? "hooray" %]
    while (my ($k, $v) = each %$extra_vars) {
        $self->{ttoptions}->{VARIABLES}->{CCM}->{$k} = $v;
    }

    return $contents;
}

=pod

=item ccm_format

Returns the CCM::TextRender instance for predefined C<format> and C<element>.
Returns undef incase the format is not defined. An array with valid formats is
exported via C<@CCM_FORMATS>.

Supported formats are:

=over

=item json

=item yaml

=item pan

=item pancxml

=back

Usage example:

    use EDG::WP4::CCM::TextRender qw(ccm_format);
    my $format = 'json';
    my $element = $config->getElement("/");
    my $trd = ccm_format($format, $element);

    if (defined $trd->get_text());
        print "$trd";
    } else {
        $logger->error("Failed to textrender format $format: $trd->{fail}")
    }

=cut

sub ccm_format
{
    my ($format, $element) = @_;

    my $trd_opts = $TEXTRENDER_FORMATS{$format};
    return if (! defined($trd_opts));

    # Format is the TextRender module
    my $trd = EDG::WP4::CCM::TextRender->new(
        $format,
        $element,
        # uppercase, no conflict with possible ncm-ccm?
        relpath => 'CCM',
        element => $trd_opts,
        );

    return $trd;
}

=pod

=back

=cut

1;
