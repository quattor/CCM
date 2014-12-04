# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
# -*- mode: cperl -*-

package EDG::WP4::CCM::XMLPanProfile;

=pod

=head1 SYNOPSIS

    EDG::WP4::CCM::XMLPanProfile->interpret_node($tag, $xmltree);

=head1 DESCRIPTION

Module that iterprets an XML profile in C<pan> format, and generates
all the needed metadata, to be inserted in the cache DB.

This metadata includes a checksum for each element in the profile, the
Pan basic type, the element's name (that will help to reconstruct the path)...

Should be used by C<EDG::WP4::CCM::Fetch> only.

This module has only one method for the outside world:

=cut

use strict;
use warnings;

use EDG::WP4::CCM::Fetch qw(ComputeChecksum);

use constant INTERPRETERS => {
    nlist   => \&interpret_nlist,
    list    => \&interpret_list,
    string  => \&interpret_scalar,
    long    => \&interpret_scalar,
    double  => \&interpret_scalar,
    boolean => \&interpret_scalar,
};

use constant VALID_ATTRIBUTES => {
    NAME        => 1,
    DERIVATION  => 1,
    CHECKSUM    => 1,
    ACL         => 1,
    ENCODING    => 1,
    DESCRIPTION => 1,
    USERTYPE    => 1
};

# Warns in case a tag in the XML profile is not known (i.e, has not a
# valid entry in the INTERPRETERS hash.
sub warn_unknown
{
    my ($content, $tag) = @_;

    warn "Cannot handle tag $tag!";
}

# Turns an nlist in the XML into a Perl hash reference with all the
# types and metadata from the profile.
sub interpret_nlist
{
    my ($content) = @_;

    my $nl = {};

    my $i = 1;

    while ($i < scalar(@$content)) {
        my $t = $content->[$i++];
        my $c = $content->[$i++];
        $nl->{$c->[0]->{name}} = __PACKAGE__->interpret_node($t, $c) if $t;
    }

    return $nl;
}

# Processess a scalar, possibly decoding its value.
sub interpret_scalar
{
    my ($content, $tag, $encoding) = @_;

    $content = $content->[2];
    if ($encoding) {
        $content = EDG::WP4::CCM::Fetch->DecodeValue($content, $encoding);
    } elsif (!defined($content) && $tag eq 'string') {
        $content = '';
    }

    return $content;
}

# Turns a list in the profile into a perl array reference in which all
# the elements have the correct metadata associated.
sub interpret_list
{
    my ($content, $tag, $encoding) = @_;

    my $l = [];
    my $i = 1;
    while ($i < scalar(@$content)) {
        my $t = $content->[$i++];
        my $c = $content->[$i++];
        push(@$l, __PACKAGE__->interpret_node($t, $c)) if $t;
    }

    return $l;
}

=pod

=head2 C<interpret_node>

Interprets an XML tree, which is assumed to have a C<format="pan">
attribute, returning the appropriate data structure with all the
attributes and values.

=cut

sub interpret_node
{
    my ($class, $tag, $content) = @_;

    my $val = {};

    my $att = $content->[0];

    $val->{TYPE} = $tag;

    while (my ($k, $v) = each(%$att)) {
        my $a = uc($k);
        if (exists(VALID_ATTRIBUTES->{$a})) {
            $val->{$a} = $v;
        } elsif ($k ne "format") {
            warn "Unknown attribute $k";
        }
    }

    my $f = INTERPRETERS->{$tag} || \&warn_unknown;
    $val->{VALUE} = $f->($content, $tag, $val->{ENCODING});

    $val->{CHECKSUM} ||= ComputeChecksum($val);
    return $val;
}

1;
