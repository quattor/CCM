#!/usr/bin/perl
# -*- mode: cperl -*-

use strict;
use warnings;

use Test::More tests => 1;
use EDG::WP4::CCM::XMLPanProfile;
use CAF::FileEditor;
use EDG::WP4::CCM::Fetch;
use Test::Deep;

sub compile_profile
{
    system("cd src/test/resources && panc -x pan profile.pan");
}

my $fh = CAF::FileEditor->new("src/test/resources/profile.xml");
my $t = EDG::WP4::CCM::Fetch->Parse("$fh");

my $reference_result = EDG::WP4::CCM::Fetch->Interpret($t);
my $our_result = EDG::WP4::CCM::XMLPanProfile->interpret_node(@$t);
cmp_deeply($reference_result, $our_result, "Our result matches the old implementation");
