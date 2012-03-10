#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;

use Test::More tests => 1;
use EDG::WP4::CCM::XMLDBProfile;
use EDG::WP4::CCM::Fetch qw(ComputeChecksum);
use CAF::FileEditor;
use Test::Deep;


=pod

=head1 SYNOPSIS

Tests for the XMLDB XML interpreter.

The module is a major refactoring of the previous interpreter, and the
output must be identical in both case.

For reference, we include here the previous implementation, that must
be removed from L<EDG::WP4::CCM::Fetch>

=cut


sub compile_profile
{
    system("cd src/test/resources && panc -x xmldb profile.pan");
}

compile_profile();


sub InterpretNodeXMLDB
{

    # Turn an XML parse node -- a (tag, content) pair -- into a Perl hash
    # representing the corresponding profile data structure.

    my ($tag, $content, $collapse) = @_;
    my $att = $content->[0];
    my $val = {};

    # For XMLDB, the tag is the element name (except for special
    # case below for encoded tags).
    $val->{NAME} = $tag;

    # Default type if not specified is an nlist.
    $val->{TYPE} = 'nlist';

    # Deal with all of the attributes.
    foreach my $a (keys %$att) {
        if ($a eq 'type') {
            $val->{TYPE} = $att->{$a};
        } elsif ($a eq 'derivation') {
            $val->{DERIVATION} = $att->{$a};
        } elsif ($a eq 'checksum') {
            $val->{CHECKSUM} = $att->{$a};
        } elsif ($a eq 'acl') {
            $val->{ACL} = $att->{$a};
        } elsif ($a eq 'encoding') {
            $val->{ENCODING} = $att->{$a};
        } elsif ($a eq 'description') {
            $val->{DESCRIPTION} = $att->{$a};
        } elsif ($a eq 'utype') {
            $val->{USERTYPE} = $att->{$a};
        } elsif ($a eq 'unencoded') {
	    # Special case for encoded tags.
            $val->{NAME} = $att->{$a};
        } else {
            # ignore unknown attribute
        }
    }

    # Pull out the type for convenience and the list depth.  Depth of
    # zero means it is not a list.  Depth of one or higher gives the
    # dimensionality of the list.
    my $type = $val->{TYPE};
    my $my_depth = (defined($att->{list})) ? int($att->{list}) : 0;

    if (($type eq 'nlist')) {

	# Flag to see if this node is eligible to be "collapsed".
	my $collapse = 0;

	# Process nlist and the top-level of lists.
        my $nlist = {};
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];

	    # Ignore all but text nodes.  May also be a list element
            # which has already been processed before.
            if ($t ne '0' and $t ne '') {

		my $a = $c->[0];
		my $child_depth = (defined($a->{list})) ? int($a->{list}) : 0;

		# Is the child a list?
		if ($child_depth==0) {

		    # No, just add the child normally.  Be careful,
		    # with encoded tags the child's name may change.
		    my $result = InterpretNodeXMLDB($t, $c);
		    $nlist->{$result->{NAME}} = $result;

		} else {

		    # This is the head of a list, create an extra
		    # level.  This may be removed later.  Check to see
		    # if this is necessary.
		    if (($my_depth > 0) and ($child_depth>$my_depth)) {
			$collapse = 1;
		    }

		    # First, create a new node to handle the list
		    # element.
		    my $vallist = {};
		    $vallist->{NAME} = $t;
		    $vallist->{TYPE} = 'list';

		    # Create a list for the value and process the
		    # current node to add to it.
		    my $list = [];
		    push @$list, InterpretNodeXMLDB($t, $c);

		    # Search through the rest of the entries to see if
		    # there are other list elements from this list.
		    my $j = $i;
		    while ($j < scalar @$content) {
			my $t2 = $content->[$j++];
			my $c2 = $content->[$j++];

			# Same name and child is a list.
			if ($t eq $t2) {
			    my $child_depth2 = $c2->[0]->{list};
			    $child_depth2 = 0 unless defined($child_depth2);

			    # Push the value of this node onto the
			    # list, but also zero the name so that it
			    # isn't processed twice.
			    if ($child_depth == $child_depth2) {
				push @$list, InterpretNodeXMLDB($t2, $c2);
				$content->[$j-2] = '0';
			    }
			}
		    }

		    # Complete the node and add it the the nlist
		    # parent.
		    $vallist->{VALUE} = $list;
		    #$vallist->{CHECKSUM} = ComputeChecksum($vallist);
		    $nlist->{$t} = $vallist;

		}
	    }
        }

	# Normally just give the value of the nlist to val.  However,
        # if we're embedded into a multidimensional list, cheat the
        # remove an unnecessary level.  Just switch the $vallist
	# reference for $val.
	if (! $collapse) {

	    # Normal case.  Just set the value to the hash.
	    $val->{VALUE} = $nlist;

	} else {

	    # Splice and dice.  Remove unnecessary level.

	    # Extra error checking.  The list should have exactly one
	    # key in it.
	    my $count = scalar (keys %$nlist);
	    if ($count!=1) {

		# This is an error.  Recover by essentially doing
		# nothing.  But print the information.
		warn("multidimensional list fixup failed; " .
			    "hash has multiple values");
		$val->{VALUE} = $nlist
	    }

	    # Switch the reference.
	    $val = $nlist->{(keys %$nlist)[0]};
	}

    } elsif ($type eq 'string' ||
	     $type eq 'double' ||
	     $type eq 'long' ||
	     $type eq 'boolean' ||
	     $type eq 'fetch' ||
	     $type eq 'stream' ||
	     $type eq 'link') {

        # decode if required
        if (defined $val->{ENCODING}) {
            $val->{VALUE} = EDG::WP4::CCM::Fetch->DecodeValue($content->[2], $val->{ENCODING});
        } else {
	    # CAL # Empty element causes undefined context.  This
            # shows up with empty strings.  Guard against this.
	    if (defined($content->[2])) {
		$val->{VALUE} = $content->[2];
	    } elsif ($type eq 'string') {
		$val->{VALUE} = '';
	    }
        }

    } else {
        # unknown type: should issue warning, at least
    }

    # compute checksum if missing
    if (not defined $val->{CHECKSUM}) {
        #$val->{CHECKSUM} = ComputeChecksum($val);
    }

    return $val;
}


=pod

The test is trivial: just grab a Pan-formatted XML, parse it and
interpret it with the previous and with the current interpreters. They
must be identical.

=cut

my $fh = CAF::FileEditor->new("src/test/resources/profile.xml");
my $t = EDG::WP4::CCM::Fetch->Parse("$fh");
my $reference_result = InterpretNodeXMLDB(@$t);
note(explain($t));
note(explain($reference_result));
my $our_result = EDG::WP4::CCM::XMLDBProfile->interpret_node(@$t);
note(explain($our_result));
cmp_deeply($our_result, $reference_result,
	   "Our result matches the old implementation");
