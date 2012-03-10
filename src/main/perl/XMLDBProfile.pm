# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
# -*- mode: cperl -*-

package EDG::WP4::CCM::XMLDBProfile;

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
use Carp;

$SIG{__DIE__} = \&confess;

use constant TOPLEVEL_TYPE => 'nlist';


use constant VALID_ATTRIBUTES => {
				  unencoded => 'NAME',
				  derivation => 'DERIVATION',
				  checksum => 'CHECKSUM',
				  acl => 'ACL',
				  encoding => 'ENCODING',
				  description => 'DESCRIPTION',
				  utype => 'USERTYPE',
				  type => 'TYPE',
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
    my ($content, $tag) = @_;

    my $nl = {};

    warn "nlist with tag $tag";

    while (@$content) {
	shift(@$content) for (1..2);
	# Ooops, I'm the heading of a list!
	$tag = shift(@$content);
	if ($content->[1]) {
	    warn "List heading with tag $tag and content ",
		join("\t", @{$content->[0]});
	    $nl->{$tag} = { NAME => $tag,
			    TYPE => 'list',
			    VALUE => interpret_list($tag, $content)};
	} else {
	    warn "real nlist with tag ", $content->[0];
	    $nl->{$tag} =  __PACKAGE__->interpret_node($tag,
						       $content->[1]);
	}
    }
    return $nl;
}


# Processess a scalar, possibly decoding its value.
sub interpret_scalar
{
    my ($content, $tag, $encoding) = @_;

    warn("I'm here and @$content");
    $content = $content->[1];
    warn "Chose scalar content $content";
    if ($encoding) {
	$content = EDG::CCM::WP4::Fetch->DecodeValue($content, $encoding);
    } elsif (!defined($content) && $tag eq 'string') {
	$content = '';
    }

    return $content;
}

# Turns a list in the profile into a perl array reference in which all
# the elements have the correct metadata associated.
sub interpret_list
{
    my ($tag, $content, $type) = @_;

    my $l = [];
    while (@$content) {
	my $c = shift(@$content);
	shift(@$content) for (1..2);
	warn("List contents to process: ", join("\t", @$c));
	push(@$l, __PACKAGE__->interpret_node($tag, $c));
	warn "List node contents: ", join("\t", (@{$content}[0..2]));
	last if ($content->[0]);
	shift(@$content);
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
    my ($class, $tag, $content)  = @_;

    my $val = {};

    my $att = $content->[0];

    $val->{NAME} = $tag;
    warn "tag=$tag, att=", join(" ", %$att);


    while (my ($k, $v) = each(%$att)) {
	if (exists(VALID_ATTRIBUTES->{$k})) {
	    $val->{VALID_ATTRIBUTES->{$k}} = $v;
	} elsif ($k ne "format" && $k ne "list") {
	    warn "Unknown attribute $k";
	}
    }

    if ($val->{TYPE}) {
	shift(@$content);
	$val->{VALUE} = interpret_scalar($content, $tag);
    } else {
	shift(@$content);
	$val->{VALUE} = interpret_nlist($content, $tag);
	$val->{TYPE} = 'nlist';
    }

    #$val->{CHECKSUM} ||= ComputeChecksum($val);
    return $val;
}

1;
