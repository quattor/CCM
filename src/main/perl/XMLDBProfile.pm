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
    my ($class, $tag, $content) = @_;

    my $nl = {};

    my $h;


    while (@$content) {
	$tag = shift(@$content);
	my $c = $content->[0];
	if (exists($c->[0]->{list})) {
	    $nl->{$tag} = { NAME => $tag,
			    TYPE => 'list',
			    VALUE => $class->interpret_list($tag, $content)
			  };
	} else {
	    $nl->{$tag} = $class->interpret_node($tag, $c);
	    shift(@$content) for(1..3);
	}
	$nl->{$tag}->{CHECKSUM} ||= ComputeChecksum($nl->{$tag});
    }
    return $nl;
}


# Processess a scalar, possibly decoding its value.
sub interpret_scalar
{
    my ($content, $tag, $encoding) = @_;

    $content = $content->[1];
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
    my ($class, $tag, $content) = @_;

    my $l = [];
    while (@$content) {
	my $c;
	do {
	    $c = shift(@$content)
	} while(!ref($c));
	# Peek the next node to check if it is a list
	my $h;
	if (scalar(@$c) >= 5 && exists($c->[4]->[0]->{list})) {
	    $h = \&interpret_list;
	}
	push(@$l, __PACKAGE__->interpret_node($tag, $c, $h));
	shift(@$content) for (1..2);
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
    my ($class, $tag, $content, $container_handler) = @_;

    $container_handler ||= \&interpret_nlist;

    my $val = {NAME => $tag};

    my $atts = shift(@$content);

    while (my ($k, $v) = each(%$atts)) {
	if (exists(VALID_ATTRIBUTES->{$k})) {
	    $val->{VALID_ATTRIBUTES->{$k}} = $v;
	} else {
	    #warn "Unknown attribute $k with value $v!!";
	}
    }

    if (@$content) {
	if (scalar(@$content) == 2) {
	    $val->{VALUE} = interpret_scalar($content);
	} else {
	    shift(@$content) for(1..2);
	    $val->{VALUE} = $container_handler->($class, $tag, $content);
	    $val->{TYPE} = ref($val->{VALUE}) eq 'HASH' ? 'nlist' : 'list';
	}
    }

    $val->{CHECKSUM} ||= ComputeChecksum($val);
    return $val;
}

1;
