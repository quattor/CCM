#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More tests => 4;
use EDG::WP4::CCM::Fetch;
use Cwd;

my $f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				   CONFIG => 'src/test/resources/ccm.cfg',
				   BASE_URL => "file://" . getcwd()});
ok($f, "Fetch profile created");
is($f->{PROFILE_URL}, "file://" . getcwd() . "src/test/resources/profile.xml",
   "Profile URL correctly set");
my $pf = $f->retrieve($f->{PROFILE_URL}, "target/test-output", 0);
ok(defined($pf), "Received something valid");
isa_ok($pf, "CAF::FileWriter");


