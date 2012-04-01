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
use XML::Parser;
use EDG::WP4::CCM::Fetch qw(ComputeChecksum);
use File::Path qw(make_path);

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
    make_path('target/test/json');
    system("cd src/test/resources && panc -x $type --output-dir=../../../target/test/json simpleprofile.pan");
}



=pod

The test is trivial: just grab a Pan-formatted XML, parse it and
interpret it with the previous and with the current interpreters. They
must be identical.

=cut

compile_profile("pan");
compile_profile("json");
my $fh = CAF::FileEditor->new("target/test/json/simpleprofile.xml");
my $t = XML::Parser->new(Style => 'Tree')->parse("$fh");
my $reference_result = EDG::WP4::CCM::XMLPanProfile->interpret_node(@$t);
$fh = CAF::FileEditor->new("target/test/json/simpleprofile.json");
note("Profile contents: $fh");
$t = decode_json("$fh");
note("Tree=", explain($t));
my $our_result = EDG::WP4::CCM::JSONProfile->interpret_node(profile => $t);
cmp_deeply($our_result, $reference_result, "Our result matches the old implementation");
note("Reference=", explain($reference_result));
note("Our=", explain($our_result));
