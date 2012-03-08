#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More tests => 4;
use EDG::WP4::CCM::Fetch;
use Cwd qw(getcwd);

my $f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				   CONFIG => 'src/test/resources/ccm.cfg'});
ok($f, "Fetch profile created");
is($f->{PROFILE_URL}, "https://www.google.com",
   "Profile URL correctly set");

my $url = sprintf('file://%s/src/test/resources/profile.xml', getcwd());
$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CONFIG => 'src/test/resources/ccm.cfg',
				PROFILE_URL => $url});
is($f->{PROFILE_URL}, $url, "file:// URL accepted");
my $pf = $f->retrieve($f->{PROFILE_URL}, "target/test-output", 0);
isa_ok($pf, "CAF::FileWriter");


