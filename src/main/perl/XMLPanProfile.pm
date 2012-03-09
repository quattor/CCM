# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
# -*- mode: cperl -*-

package EDG::WP4::CCM::XMLPanProfile;

=pod

=head1 SYNOPSIS

Module that iterprets an XML profile in C<pan> format, and generates
all the desired metadata, to be inserted in the cache DB.

=cut

use strict;
use warnings;

use parent "CAF::Reporter";

use constant INTERPRETERS => {
			      nlist => \&interpret_nlist,
			      list => \&interpret_list,
			      string => \&interpret_scalar,
			      long => \&interpret_scalar,
			      double => \&interpret_scalar,
			      boolean => \&interpret_scalar,
			     };

use constant VALID_ATTRIBUTES => {
				  NAME => 1,
				  DERIVATION => 1,
				  CHECKSUM => 1,
				  ACL => 1,
				  ENCODING => 1,
				  DESCRIPTION => 1,
				  USERTYPE => 1
				 };

sub warn_unknown
{
    my ($tag, $content) = @_;

    warn "Cannot handle tag $tag!";
}


sub interpret_nlist
{
    my ($self, $content) = @_;

    my $rt = {};
}

sub interpret_scalar
{}

sub interpret_list
{}


sub interpret_node
{
    my ($self, $tag, $content)  = @_;

    my $val = {};

    my $att = $content->[0];

    $val->{TYPE} = $tag;

    while (my ($k, $v) = each(%$att)) {
	my $a = uc($k);
	if (exists(VALID_ATTRIBUTES->{$a})) {
	    $val->{$a} = $v;
	}
    }

    my $f = INTERPRETERS->{$tag} || \&warn_unknown;
    $val->{VALUE} = $f->($content);
}


1;
