#!/usr/bin/perl -w

#
# cache Path.pm test script
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::Path qw (escape unescape);

my $ec = LC::Exception::Context->new->will_store_errors;

=head2 escape / unescape

=cut

is(unescape(escape("kernel-2.6.32")), "kernel-2.6.32",
   "Escaping and unescaping cancel each other out");

is(escape("kernel-2.6.32"), "kernel_2d2_2e6_2e32",
   "Escaping works as expected");
is(unescape("kernel_2d2_2e6_2e32"), "kernel-2.6.32",
   "Unescaping works as expected");

=head2 path_split

=cut

sub sok {
    my ($path, $res, $msg, $single) = @_;
    unshift(@$res, '') if ! $single; # the empty string after split from the leading / or single subpath
    is_deeply([EDG::WP4::CCM::Path::path_split($path)], $res, $msg);
};

sok("", [], "Split empty string", 1);
sok("/a", [qw(a)], "Split single subdir");
sok("a", [qw(a)], "Split single element string", 1);
sok("/a/b/c", [qw(a b c)], "Basic split");
sok("/a/{/x/y/z}/b/c", [qw(a _2fx_2fy_2fz b c)], "Split single escaped path");
sok("/{/x/y/z}/b/{/sys/fs}/services/{/}", [qw(_2fx_2fy_2fz b _2fsys_2ffs services _2f)], "Split 3 escaped paths");
sok("{/single/subpath}", [qw(_2fsingle_2fsubpath)], "Split single subpath", 1);
sok("/{/x/y/z}/{/sys/fs}/{/}", [qw(_2fx_2fy_2fz _2fsys_2ffs _2f)], "Split 3 adjacent escaped paths");

=head2 new

=cut

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

=head2 toString / stringification

=cut

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c/"),
    'EDG::WP4::CCM::Path->new("/a/b/c/")');
is ($path->toString(), "/a/b/c", "$path->toString()");
is("$path", "/a/b/c", "path stringification");

=head2 up / down

=cut

ok ($path->up() && ($path->toString() eq "/a/b"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/a"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/"), "$path->up()");

ok ($path->down("b") && ($path->toString() eq "/b"), '$path->down("b")');
eok ($ec, $path->down("/b"), '$path->down("/b")');
eok ($ec, $path->down(""), '$path->down("")');

ok ($path->down("{/a/b/c}") && ($path->toString() eq "/b/_2fa_2fb_2fc"), '$path->down("{/a/b/c}")');


=head2 merge

=cut

$path = EDG::WP4::CCM::Path->new("/a/b/c");
isa_ok($path, "EDG::WP4::CCM::Path", "new returns EDG::WP4::CCM::Path instance");
my $newpath = $path->merge();
isa_ok($newpath, "EDG::WP4::CCM::Path", "merge returns EDG::WP4::CCM::Path instance 1");
is_deeply($newpath, $path, "Merge with empty subpaths returns clone");
is("$newpath", "$path", "Stringification ok 1");

$newpath = $path->merge("d", "e", "f", "{/a/b/c}");
isa_ok($newpath, "EDG::WP4::CCM::Path", "merge returns EDG::WP4::CCM::Path instance 2");
is("$newpath", "$path/d/e/f/_2fa_2fb_2fc", "Stringification ok 2");


done_testing();
