#!/usr/bin/perl -w

#
# cache Path.pm test script
#
# $Id: test-path.pl,v 1.5 2006/06/26 14:20:43 gcancio Exp $
#
# Copyright (c) 2001 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

BEGIN {unshift(@INC,'/usr/lib/perl')};

use strict;
use Test::More qw(no_plan);
use myTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::Path qw ();

my $ec = LC::Exception::Context->new->will_store_errors;

eok($ec, EDG::WP4::CCM::Path->new("///a/b/c"), 
    'EDG::WP4::CCM::Path->new("///a/b/c")');
eok($ec, EDG::WP4::CCM::Path->new("//a/b/c"), 
    'EDG::WP4::CCM::Path->new("//a/b/c")');
eok($ec, EDG::WP4::CCM::Path->new("a/b/c"), 
    'EDG::WP4::CCM::Path->new("a/b/c")');
eok ($ec, EDG::WP4::CCM::Path->new(""),
    'EDG::WP4::CCM::Path->new("")');
ok (EDG::WP4::CCM::Path->new("/"),
    'EDG::WP4::CCM::Path->new("/")');

my $path;

ok ($path = EDG::WP4::CCM::Path->new(),
    'EDG::WP4::CCM::Path->new()');
is ($path->toString(), "/", "$path->toString()");
ok ($path = EDG::WP4::CCM::Path->new("/"),
    'EDG::WP4::CCM::Path->new("/")');
is ($path->toString(), "/", "$path->toString()");

ok ($path = EDG::WP4::CCM::Path->new("/a"),
    'EDG::WP4::CCM::Path->new("/a")');
is ($path->toString(), "/a", "$path->toString()");

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c"),
    'EDG::WP4::CCM::Path->new("/a/b/c")');
is ($path->toString(), "/a/b/c", "$path->toString()");

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c/"),
    'EDG::WP4::CCM::Path->new("/a/b/c/")');
is ($path->toString(), "/a/b/c", "$path->toString()");

ok ($path->up() && ($path->toString() eq "/a/b"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/a"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/"), "$path->up()");

ok ($path->down("b") && ($path->toString() eq "/b"), '$path->down("b")');
eok ($ec, $path->down("/b"), '$path->down("/b")');
eok ($ec, $path->down(""), '$path->down("")');
