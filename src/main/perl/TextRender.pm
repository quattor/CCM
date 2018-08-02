#${PMpre} EDG::WP4::CCM::TextRender${PMpost}

use CAF::TextRender 18.6.0 qw($YAML_BOOL_PREFIX);
use Readonly;
use EDG::WP4::CCM::TextRender::Scalar qw(%ELEMENT_TYPES);
use EDG::WP4::CCM::Path qw(escape unescape);
use XML::Parser;
use parent qw(CAF::TextRender Exporter);

our @EXPORT_OK = qw(%ELEMENT_CONVERT @CCM_FORMATS ccm_format);

# private instance for xml_string processing
my $_xml_parser = XML::Parser->new(Style => 'Tree');

# test if C<txt> is valid xml by trying to parse it with XML::Parser
sub _is_valid_xml
{
    my $txt = shift;

    # XML::Parser->parse uses 'die' with invalid xml.
    my $tag = "really_really_random_tag";

    local $@;
    my $t = eval {$_xml_parser->parse("<$tag>$txt</$tag>");};
    return $@ ? 0 : 1;
}

# Args arrayref C<value> and separator C<sep>
# If the first element is a scalar (or undef),
# return joined string with separator (with undef converted to empty string).
# If first element is not a scalar, return original arrayref.
# In all other cases (empty arrayref, undef), return empty string.
our $_arrayref_join = sub {
    my ($value, $sep) = @_;

    my $res = '';
    if ($value && @$value) {
        $res = ref($value->[0]) ? $value : join($sep, map {defined($_) ? "$_" : "" } @$value );
    };
    return $res;
};

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
        use warnings FATAL => qw(numeric);
        # the 0+ operator of value is used
        return 0 + $value;
    },
    'cast_double' => sub {
        my $value = shift;
        use warnings FATAL => qw(numeric);
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
    'arrayref_join_comma' => sub {
        return &$_arrayref_join(shift, ',');
    },
    'arrayref_join_space' => sub {
        return &$_arrayref_join(shift, ' ');
    },
    'unescape' => sub {
        return unescape(shift);
    },
};

# Update the ccm_format pod with new formats
Readonly::Hash my %TEXTRENDER_FORMATS => {
    json => {}, # No opts
    jsonpretty => {}, # No opts (same as json)
    ncmquery => { truefalse => 1 },
    pan => { truefalse => 1, doublequote => 1},
    pancxml => { truefalse => 1, xml => 1 },
    query => { truefalse => 1, singlequote => 1 },
    tabcompletion => {},
    yaml => {}, # No opts
};

Readonly::Array our @CCM_FORMATS => sort keys %TEXTRENDER_FORMATS;;

=pod

=head1 NAME

    CCM::TextRender - Class for rendering structured text using Element instances

=head1 DESCRIPTION

This class is an extension of the C<CAF::TextRender> class; with the main
difference the support of a C<EDG::WP4::CCM::CacheManager::Element> instance as contents.

=head2 Private methods

=over

=item C<_initialize>

Initialize the process object. Arguments:

=over

=item module

The rendering module to use (see B<CAF::TextRender> for details).

CCM provides following additional builtin modules:

=over

=item general

using TT to render a C<Config::General> compatible file.
(This is an alias for the C<CCM/general> TT module).

Contents is a hashref (does not require a C<Element> instance),
with key/value pairs generated according to
the basetype of the value as follows:

=over

=item scalar

converted in a single line
    <key> <value>

=item arrayref of scalars

converted in multiple lines as follows
    <key> <scalar element0>
    <key> <scalar element1>
    ...

=item hashref

generates a block with format
    <"key">
        <recursive rendering of the value>
    </"key">

=item arrayref of hashref

generates series of blocks
    <"key">
        <recursive rendering of the element0>
    </"key">
    <"key">
        <recursive rendering of the element1>
    </"key">
    ...

=back

(Whitespace in the block name is enforced with double quotes.)

=back

=item contents

C<contents> is either a hash reference holding the contents to pass to the rendering module;
or a C<EDG::WP4::CCM::CacheManager::Element> instance, on which C<getTree> is called with any C<element>
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

=item joincomma

Convert list of scalars in comma-separated list of strings
(if first element is scalar). List where first element is
non-scalar is not converted (but any of the nested list could).

=item joinspace

Convert list of scalars in space-separated list of strings
(if first element is scalar). List where first element is
non-scalar is not converted (but any of the nested list could).

Caveat: is preceded by C<joincomma> option.

=item unescapekey

Unescape all dict keys.

=item lowerkey

Convert all dict keys to lowercase.

=item upperkey

Convert all dict keys to uppercase.

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

    # The general alias
    if ($module eq 'general' && ! defined($opts{relpath})) {
        $opts{relpath} = 'CCM';
    }

    return $self->SUPER::_initialize($module, $contents, %opts);
}

# Modify the elementopts attribute based on selected module
sub _modify_elementopts_module
{
    my ($self) = @_;

    my $elopts = $self->{elementopts};
    foreach my $module (qw(json jsonpretty yaml)) {
        if ($self->{module} && $self->{module} eq $module &&
            ! defined( $elopts->{$module})) {
            $elopts->{$module} = 1;
            last;
        }
    }
    $elopts->{json} = 1 if $elopts->{jsonpretty};
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

    if ($elopts->{joincomma}) {
        push(@{$opts{convert_list}}, $ELEMENT_CONVERT{arrayref_join_comma});
    } elsif ($elopts->{joinspace}) {
        push(@{$opts{convert_list}}, $ELEMENT_CONVERT{arrayref_join_space});
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

    if ($elopts->{unescapekey}) {
        push(@{$opts{convert_key}}, $ELEMENT_CONVERT{unescape});
    }

    if ($elopts->{lowerkey}) {
        push(@{$opts{convert_key}}, $ELEMENT_CONVERT{lower});
    } elsif ($elopts->{upperkey}) {
        push(@{$opts{convert_key}}, $ELEMENT_CONVERT{upper});
    };

    return %opts;
}

# Return the validated contents. Either the contents are a hashref
# (in that case they are left untouched) or a C<EDG::WP4::CCM::CacheManager::Element> instance
# in which case C<getTree> is called together with the relevant C<elementopts>
sub make_contents
{
    my ($self) = @_;

    my $contents;

    my $ref = ref($self->{contents});

    # Additional variables available to both regular hashref and element
    my $extra_vars = {
        ref => sub { return ref($_[0]) },
        is_scalar => sub { my $r = ref($_[0]); return (! $r || $r eq 'EDG::WP4::CCM::TextRender::Scalar');  },
        is_list => sub { my $r = ref($_[0]); return ($r && ($r eq 'ARRAY'));  },
        is_hash => sub { my $r = ref($_[0]); return ($r && ($r eq 'HASH'));  },
        escape => \&escape,
        unescape => \&unescape,
        is_in_list => sub {
            # return if 2nd arg (element) is in 1st arg (list)
            # returns false if 1st arg is not a list
            # returns false if 2nd arg is not a scalar
            my $r = ref($_[0]);
            return if !($r && ($r eq 'ARRAY'));
            return if !defined($_[1]) || ref($_[1]) ne '';

            return (grep {$_[1] eq $_} @{$_[0]}) ? 1 :0;
        },
    };


    if($ref && ($ref eq "HASH")) {
        $contents = $self->{contents};
    } elsif ($ref && UNIVERSAL::can($self->{contents}, 'can') &&
             $self->{contents}->isa('EDG::WP4::CCM::CacheManager::Element')) {
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

        # Last step: add convert methods for scalar types to CCM::TextRender::Scalar
        # if the render method is TT
        if ($self->{method_is_tt}) {
            foreach my $type (qw(boolean string long double)) {
                push(@{$opts{"convert_$type"}}, sub {
                    my $scalartype = $ELEMENT_TYPES{(uc $type)};
                    return EDG::WP4::CCM::TextRender::Scalar->new($_[0], $scalartype);
                     });
            }
        }

        $contents = $self->{contents}->getTree($depth, %opts);

        # Add the path as an arrayref that can be joined to the correct path
        # $self->{contents} gets replaced
        my $orig_contents = $self->{contents};
        $extra_vars->{element} = {
            path => $self->{contents}->getPath(), # data, not a function
            ccm_format => sub {
                # run ccm_format on element from relative path with eol=0
                my ($format, $relpath) = @_;
                return if $relpath =~ m/^\//;

                # prepare full path relative to current path
                my $path = $orig_contents->getPath();
                $path =~ s/\/+$//;
                $path .= "/$relpath";
                $path =~ s/\/+$//;

                my $config = $orig_contents->getConfiguration();
                if ($config->elementExists($path)) {
                    my $el = $config->getElement($path);
                    return ccm_format($format, $el, eol => 0);
                }
            },
        }

    } else {
        return $self->fail("Contents passed is neither a hashref or ",
                           "a EDG::WP4::CCM::CacheManager::Element instance ",
                           "(ref ", ref($self->{contents}), ")");
    }


    # Make the full contents available (e.g. to access the root keys)
    # Must be a level-1 copy (can't touch the values, see e.g. json/yaml)
    # TODO: investigate Storable dclone (but will it make unmodified copies of the values?)
    # TODO: handle scalars converted to array(ref)s?
    $ref = ref($contents);
    if(! $ref) {
        # This can be a scalar (e.g. regular getTree on scalar element)
        $extra_vars->{contents} = $contents;
    } elsif ($ref eq "HASH") {
        $extra_vars->{contents} = { %$contents };
    } elsif ($ref eq "ARRAY") {
        $extra_vars->{contents} = [ @$contents ];
    } else {
        # Typically a scalar that is converted to another instance
        $extra_vars->{contents} = bless { %$contents }, $ref;
    }


    # Add extra_vars to the CCM namespace
    # To be used in TT as follows: [% CCM.is_hash(myvar) ? "hooray" %]
    while (my ($k, $v) = each %$extra_vars) {
        $self->{ttoptions}->{VARIABLES}->{CCM}->{$k} = $v;
    }

    # The returned contents here are passed via CAF::TextRender::tt
    # to template->process; and are interpreted as the parameters available
    # in the TT file. Because of this, we can only allow a hashref here.
    # If you want to support rendering from non-hashref, you can but you have to
    # use the CCM.contents and not expect any available variables.
    $contents = {} if ($self->{method_is_tt} && ($ref ne 'HASH'));

    return $contents;
}

=pod

=item ccm_format

Returns the CCM::TextRender instance for predefined C<format> and C<element>.
All options are passed to CCM::TextRender initialisation.
Returns undef incase the format is not defined. An array with valid formats is
exported via C<@CCM_FORMATS>.

Supported formats are:

=over

=item json

=item jsonpretty

=item pan

=item pancxml

=item query

=item yaml

=back

Usage example:

    use EDG::WP4::CCM::TextRender qw(ccm_format);
    my $format = 'json';
    my $element = $config->getElement("/");
    my $trd = ccm_format($format, $element);

    if (defined $trd->get_text()) {
        print "$trd";
    } else {
        $logger->error("Failed to textrender format $format: $trd->{fail}")
    }

=cut

sub ccm_format
{
    my ($format, $element, %opts) = @_;

    my $trd_opts = $TEXTRENDER_FORMATS{$format};
    return if (! defined($trd_opts));

    # Format is the TextRender module
    my $trd = EDG::WP4::CCM::TextRender->new(
        $format,
        $element,
        # uppercase, no conflict with possible ncm-ccm?
        relpath => 'CCM',
        element => $trd_opts,
        %opts
        );

    return $trd;
}

=pod

=back

=cut

1;
