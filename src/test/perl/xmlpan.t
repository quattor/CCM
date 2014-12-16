#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;

use Test::More tests => 1;
use EDG::WP4::CCM::XMLPanProfile;
use EDG::WP4::CCM::Fetch qw(ComputeChecksum);
use CAF::FileEditor;
use Test::Deep;
use File::Path qw(make_path);

=pod

=head1 SYNOPSIS

Tests for the Pan XML interpreter.

The module is a major refactoring of the previous interpreter, and the
output must be identical in both cases.

For reference, we include here the previous implementation, that must
be removed from L<EDG::WP4::CCM::Fetch>, as the C<InterpretNode> method.

=cut


sub compile_profile
{
    make_path("target/test/pan");
    system("cd src/test/resources && panc --output-dir ../../../target/test/pan --formats pan profile.pan");
}

sub InterpretNode
{

    # Turn an XML parse node -- a (tag, content) pair -- into a Perl hash
    # representing the corresponding profile data structure.

    my ($tag, $content) = @_;
    my $att = $content->[0];
    my $val = {};

    # deal with attributes
    $val->{TYPE} = $tag;
    foreach my $a (keys %$att) {
        if ($a eq 'name') {
            $val->{NAME} = $att->{$a};
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
        } elsif ($a eq 'type') {
            $val->{USERTYPE} = $att->{$a};
        } else {
            # unknown attribute
        }
    }

    # work out value
    if ($tag eq 'nlist') {
        my $nlist = {};
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];
            if ($t ne '0' and $t ne '') {
                # ignore text between elements
                my $a = $c->[0];
                my $n = $a->{name};
                $nlist->{$n} = InterpretNode($t, $c);
            }
        }
        $val->{VALUE} = $nlist;
    } elsif ($tag eq 'list') {
        my $list = [];
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];
            if ($t ne '0' and $t ne '') {
                # ignore text between elements
                push @$list, InterpretNode($t, $c);
            }
        }
        $val->{VALUE} = $list;
    } elsif ($tag eq 'string' or
             $tag eq 'double' or
             $tag eq 'long' or
             $tag eq 'boolean') {
        # decode if required
        if (defined $val->{ENCODING}) {
            $val->{VALUE} = EDG::WP4::CCM::Fetch::DecodeValue($content->[2], $val->{ENCODING});
        } else {
            $val->{VALUE} = $content->[2];
        }
    } else {
        # unknown type: should issue warning, at least
    }
    # compute checksum if missing
    if (not defined $val->{CHECKSUM}) {
        $val->{CHECKSUM} = ComputeChecksum($val);
    }

    return $val;
}

=pod

The test is trivial: just grab a Pan-formatted XML, parse it and
interpret it with the previous and with the current interpreters. They
must be identical.

=cut

compile_profile();

my $fh = CAF::FileEditor->new("target/test/pan/profile.xml");
my $t = XML::Parser->new(Style => 'Tree')->parse("$fh");

my $reference_result = InterpretNode(@$t);
my $our_result = EDG::WP4::CCM::XMLPanProfile->interpret_node(@$t);
cmp_deeply($our_result, $reference_result, "Our result matches the old implementation");

done_testing();
