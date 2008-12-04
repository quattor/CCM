#!/usr/bin/perl -w

#
# cache SyncFile.pm test script
# IMPORTANT: it does not test synchronisation issues
#
# $Id: test-syncfile.pl,v 1.6 2006/06/26 14:20:43 gcancio Exp $
#
# Copyright (c) 2001 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#
BEGIN {unshift(@INC,'/usr/lib/perl')};

use strict;
use Test::More qw(no_plan);
use myTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::SyncFile qw (read write);

my $fn  = "/tmp/sf-test.txt";
my $tsy = "yes";
my $tsn = "no";

my $f = EDG::WP4::CCM::SyncFile->new($fn);

ok ($f, "EDG::WP4::CCM::SyncFile->new($fn)");
ok ($f->write ($tsy), "$f->write ($tsy)");
is ($f->read (), $tsy, "$f->write ()");
is ($f->get_file_name(), $fn, "$f->get_file_name()");



