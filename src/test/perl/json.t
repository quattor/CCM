#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;

use Test::More tests => 1;
use EDG::WP4::CCM::XMLPanProfile;
use EDG::WP4::CCM::JSONProfile;
use EDG::WP4::CCM::Fetch;
use CAF::FileEditor;
use JSON::XS qw(decode_json);
use Test::Deep;


=pod

=head1 SYNOPSIS

Tests for the Pan XML interpreter.

The module is a major refactoring of the previous interpreter, and the
output must be identical in both case.

For reference, we include here the previous implementation, that must
be removed from L<EDG::WP4::CCM::Fetch>

=cut


sub compile_profile
{
    my ($type) = @_;
    system("cd src/test/resources && panc -x $type simpleprofile.pan");
}



=pod

The test is trivial: just grab a Pan-formatted XML, parse it and
interpret it with the previous and with the current interpreters. They
must be identical.

=cut

compile_profile("pan");
compile_profile("json");
my $fh = CAF::FileEditor->new("src/test/resources/simpleprofile.xml");
my $t = EDG::WP4::CCM::Fetch->Parse("$fh");
my $reference_result = EDG::WP4::CCM::XMLPanProfile->interpret_node(@$t);
$fh = CAF::FileEditor->new("src/test/resources/simpleprofile.json");
note("Profile contents: $fh");
$t = decode_json("$fh");
note("Tree=", explain($t));
my $our_result = EDG::WP4::CCM::JSONProfile->interpret_node(profile => $t);
cmp_deeply($our_result, $reference_result, "Our result matches the old implementation");
note("Reference=", explain($reference_result));
note("Our=", explain($our_result));
