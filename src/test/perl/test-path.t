#!/usr/bin/perl -w

#
# cache Path.pm test script
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok);
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
is ("$path", "/", "stringification /");

ok ($path = EDG::WP4::CCM::Path->new("/a"),
    'EDG::WP4::CCM::Path->new("/a")');
is ($path->toString(), "/a", "$path->toString()");
is ("$path", "/a", "stringification /a");

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c"),
    'EDG::WP4::CCM::Path->new("/a/b/c")');
is ($path->toString(), "/a/b/c", "$path->toString()");
is ("$path", "/a/b/c", "stringification /a/b/c");

my @paths = @$path;
# is_deeply($path, ...) tries to evaluate $path in string context first?
# so stringification kicks in, and this doesn't match anymore
is_deeply(\@paths, ['a', 'b', 'c'], "Correct array reference");

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c/"),
    'EDG::WP4::CCM::Path->new("/a/b/c/")');
is ($path->toString(), "/a/b/c", "$path->toString()");

ok ($path->up() && ($path->toString() eq "/a/b"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/a"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/"), "$path->up()");

ok ($path->down("b") && ($path->toString() eq "/b"), '$path->down("b")');
eok ($ec, $path->down("/b"), '$path->down("/b")');
eok ($ec, $path->down(""), '$path->down("")');

$path = EDG::WP4::CCM::Path->new("/a/b/c");
isa_ok($path, "EDG::WP4::CCM::Path", "new returns EDG::WP4::CCM::Path instance");
my $newpath = $path->merge();
isa_ok($newpath, "EDG::WP4::CCM::Path", "merge returns EDG::WP4::CCM::Path instance");
is_deeply($newpath, $path, "Merge with empty subpaths returns clone");
is("$newpath", "$path", "Stringification ok");

$newpath = $path->merge("d", "e", "f");
isa_ok($newpath, "EDG::WP4::CCM::Path", "merge returns EDG::WP4::CCM::Path instance");
is("$newpath", "$path/d/e/f", "Stringification ok");

done_testing();
