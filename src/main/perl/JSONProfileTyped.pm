# -*- mode: cperl -*-
# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::JSONProfileTyped;

=pod

=head1 SYNOPSIS

    EDG::WP4::CCM::JSONProfileTyped->interpret_node($tag, $jsondoc);

=head1 DESCRIPTION

Module that iterprets a JSON profile and generates all the needed
metadata, to be inserted in the cache DB.

This metadata includes a checksum for each element in the profile, the
Pan basic type, the element's name (that will help to reconstruct the path)...

Should be used by C<EDG::WP4::CCM::Fetch> only.

This module has only C<interpret_node> method for the outside world.

=head2 Type information from JSON::XS

JSON profiles don't contain any explicit type information (as opposed to the
XMLPAN output), e.g. JSON only supports 'number' where XMLPAN has 'long' and 'double'.

It is up to the JSON decoder to provide us with this additional distinction.
The JSON package C<JSON::XS> does not expose the scalar type information.

However, we try to come up with correct proper type by relying on the property that
C<JSON::XS> supports C<json_string eq encode(copy(decode(json_string)))>
(implying that the instance returned by C<decode> has the C<XS> types
(and e.g. no stringification has happened)). However, this is best effort only.

Imperative in the whole typed processing is that values from the decoded JSON
are not assigned to any variable before the type information is extraced via the
C<B::svref_2object> method. The scalar types (except for boolean) are then mapped to
the C<B> classes: C<IV> is 'long', C<PV> is 'double' and C<NV> is 'string'.
Anything else will be mapped to string (including the combined classes C<PVNV> and C<PVIV>).

TODO: The validity of this assumption is tested in the C<BEGIN{}> (and unittests).

=cut


use strict;
use warnings;

use EDG::WP4::CCM::Fetch qw(ComputeChecksum);
use JSON::XS;
use B;
use Scalar::Util qw(blessed);

$SIG{__DIE__} = \&confess;

# Turns a JSON Object (an unordered associative array) into a Perl hash
# reference with all the types and metadata from the profile.
sub interpret_nlist
{
    my ($class, $tag, $doc) = @_;

    my $nl = {};

    foreach my $k (keys %$doc) {
        my $b_obj = B::svref_2object(\$doc->{$k});
        $nl->{$k} = $class->interpret_node($k, $doc->{$k}, $b_obj);
    }
    return $nl;
}

# Turns a JSON Array (an ordered list) in the profile into a perl array reference in which all
# the elements have the correct metadata associated.
sub interpret_list
{
    my ($class, $tag, $doc) = @_;

    my $l = [];

    my $last_idx = scalar @$doc -1;
    foreach my $idx (0..$last_idx) {
        my $b_obj = B::svref_2object(\$doc->[$idx]);
        push(@$l, $class->interpret_node(undef, $doc->[$idx], $b_obj));
    }

    return $l;
}

# Map the C<B::SV> class from C<B::svref_2object> to a scalar type
# C<IV> is 'long', C<PV> is 'double' and C<NV> is 'string'.
# Anything else will be mapped to string (including the combined
# classes C<PVNV> and C<PVIV>).
# This only works due to the XS C API used by JSON::XS and if you call
# B::svref_2object directly on the value without assigning it to a
# variable first. This is no magic function that will
# "just work" on anything you throw at it.
sub get_scalar_type
{
    my $b_obj = shift;

    if (! blessed($b_obj)) {
        # what was passed?
        return 'string';
    };

    if ($b_obj->isa('B::IV')) {
        return 'long';
    } elsif ($b_obj->isa('B::NV')) {
        return 'double';
    } elsif ($b_obj->isa('B::PV')) {
        return 'string';
    }

    # TODO: log all else?
    return 'string';

}

=pod

=head2 C<interpret_node>

C<b_obj> is returned by the C<B::svref_2object()> method on the C<doc>
(ideally before C<doc> is assigned).

The initial call from C<Fetch> doesn't pass the C<b_obj> value, but that is
acceptable since we do not expect the whole JSON profile to be a single scalar value.

=cut

sub interpret_node
{
    my ($class, $tag, $doc, $b_obj) = @_;

    my $r = ref($doc);

    my $v = {};
    $v->{NAME} = $tag if $tag;
    if (!$r) {
        $v->{VALUE} = $doc;
        $v->{TYPE}  = get_scalar_type($b_obj);
    } elsif ($r eq 'HASH') {
        $v->{TYPE} = 'nlist';
        $v->{VALUE} = $class->interpret_nlist($tag, $doc);
    } elsif ($r eq 'ARRAY') {
        $v->{TYPE} = 'list';
        $v->{VALUE} = $class->interpret_list($tag, $doc);
    } elsif (JSON::XS::is_bool($doc)) {
        $v->{TYPE} = "boolean";
        $v->{VALUE} = $doc ? "true" : "false";
    } else {
        die "Unknown ref type ($r) for JSON document $doc, on $tag";
    }
    $v->{CHECKSUM} = ComputeChecksum($v);
    return $v;
}

1;
