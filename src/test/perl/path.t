#!/usr/bin/perl -w

#
# cache Path.pm test script
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::Path qw (escape unescape set_safe_unescape reset_safe_unescape);

my $ec = LC::Exception::Context->new->will_store_errors;

is_deeply(\@EDG::WP4::CCM::Path::SAFE_UNESCAPE, [
    '/software/components/filecopy/services/',
    '/software/components/metaconfig/services/',
    '/software/packages/',
    qr{/software/packages/[^/]+/},
], "List of known safe_unescape");

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

sub test_path {
    my ($patharg, $tostr, $depth, $last, $ref) = @_;
    my $pathargstr = defined $patharg ? "$patharg" : "<undef>";
    my $path = EDG::WP4::CCM::Path->new($patharg);
    isa_ok ($path, 'EDG::WP4::CCM::Path',
        "EDG::WP4::CCM::Path->new($pathargstr) returns EDG::WP4::CCM::Path instance");
    is ($path->toString(), $tostr, "path->toString() for $pathargstr");
    is($path->depth(), $depth, "depth $depth for $pathargstr");
    my $glast = $path->get_last();
    if(defined $last) {
        is($glast, $last, "last $last for $pathargstr");
    } else {
        ok(! defined($glast), "last undefined for $pathargstr")
    }
    if($ref) {
        my @paths = @$path;
        is_deeply(\@paths, $ref, "array reference for $pathargstr");
    }
};

test_path(undef, '/', 0, undef);
test_path('/', '/', 0, undef);
test_path('/a', '/a', 1, 'a');
test_path('/a/b/c', '/a/b/c', 3, 'c', ['a', 'b', 'c']);
test_path('/{/x/y/z}/b/{/sys/fs}/services/{/}',
          '/_2fx_2fy_2fz/b/_2fsys_2ffs/services/_2f',
          5, '_2f',
          [qw(_2fx_2fy_2fz b _2fsys_2ffs services _2f)]);

=head2 toString / stringification

=cut

ok ($path = EDG::WP4::CCM::Path->new("/a/b/c/"),
    'EDG::WP4::CCM::Path->new("/a/b/c/")');
is ($path->toString(), "/a/b/c", "$path->toString()");
is("$path", "/a/b/c", "path stringification");

=head2 up

=cut

ok ($path->up() && ($path->toString() eq "/a/b"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/a"), "$path->up()");
ok ($path->up() && ($path->toString() eq "/"), "$path->up()");

=head2 down

=cut

ok ($path->down("a") && ($path->toString() eq "/a"), '$path->down("a")');
# leading / is ignored
ok ($path->down("/b") && ($path->toString() eq "/a/b"), '$path->down("/b")');
# noop / ignore '/' path
ok ($path->down("") && ($path->toString() eq "/a/b"), '$path->down("")');
# compound path
ok ($path->down("c/d") && ($path->toString() eq "/a/b/c/d"), '$path->down("c/d")');

ok ($path->down("{/a/b/c}") && ($path->toString() eq "/a/b/c/d/_2fa_2fb_2fc"), '$path->down("{/a/b/c}")');

ok ($path->down("0") && ($path->toString() eq "/a/b/c/d/_2fa_2fb_2fc/0"), '$path->down("0")');

=head2 parent

=cut

$path = EDG::WP4::CCM::Path->new();
ok(! defined($path->parent()), "root path parent returns undef");
is("$path", "/", "root path unmodified after parent call");

$path = EDG::WP4::CCM::Path->new("/a/b/c");
my $parent = $path->parent();
isa_ok($parent, 'EDG::WP4::CCM::Path', 'parent returns a Path instance');
# the stringifcation of $path shows that $path itself is unmodified
is("$parent/c", "$path", "parent stringification works as expected with unmodified path");

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
# the stringifcation of $path shows that $path itself is unmodified
is("$newpath", "$path/d/e/f/_2fa_2fb_2fc", "Stringification ok 2");

=head2 _test_safe_unescape

=cut

reset_safe_unescape();
set_safe_unescape(qw(/a/b /a/b/{/a/b/c}/e/f/), qr{^/a/c/[^/]+/});
is(EDG::WP4::CCM::Path::_safe_unescape('/a/a', '_2fa_2fb_2fc'), '_2fa_2fb_2fc', 'basic _safe_unescape no matching parent');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc'), '{/a/b/c}', 'basic _safe_unescape exact stringmatch');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b/{/a/b/c}/e/f/', '_2fa_2fb_2fc'), '{/a/b/c}', 'basic _safe_unescape exact stringmatch with safe escaped parent');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/c/whatever', '_2fa_2fb_2fc'), '{/a/b/c}', 'basic _safe_unescape with compiled regexp parent');

reset_safe_unescape();

=head2 set_safe_unescape / reset_safe_unescape

=cut

$path = EDG::WP4::CCM::Path->new("/a/b/{/a/b/c}");

# parent + subpath
my @paths = qw(/a/b c /a/b {/a/b/c} /a/b/{/a/b/c}/e/f {x/y/z} /g/h {o/p/q});

my $orig = [qw(/a/b/c /a/b/_2fa_2fb_2fc /a/b/_2fa_2fb_2fc/e/f/x_2fy_2fz /g/h/o_2fp_2fq)];
my $safe_escaped = [qw(/a/b/c /a/b/{/a/b/c} /a/b/{/a/b/c}/e/f/{x/y/z} /g/h/o_2fp_2fq)];

sub test_safe_unescape
{
    my ($topath) = @_;
    my @res;
    my $idx = 0;
    while ($idx < scalar @paths) {
        my $parent = EDG::WP4::CCM::Path->new($paths[$idx++]);
        my $subpath = $paths[$idx++];

        my $parentarg = $topath ? $parent : "$parent";

        # very primitive
        $subpath =~ s/^\{//;
        $subpath =~ s/\}$//;
        $subpath = escape($subpath);

        push(@res, "$parent/".EDG::WP4::CCM::Path::_safe_unescape($parentarg, $subpath));
    };

    return \@res;
}

# return path stringifications or toString
sub make_paths_strings
{
    my ($stringify) = @_;

    my @res;
    my $idx = 0;
    while ($idx < scalar @paths) {
        my $parent = $paths[$idx++];
        my $subpath = $paths[$idx++];

        my $path_instance = EDG::WP4::CCM::Path->new("$parent/$subpath");

        push(@res, $stringify ? "$path_instance" : $path_instance->toString());
    };
    return \@res;
}


# To make sure it isn't set before, but there's no real way to check
reset_safe_unescape();
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc'), '_2fa_2fb_2fc', 'basic _safe_unescape without safe_unescape 1');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc', 1), '_2fa_2fb_2fc', 'basic _safe_unescape trim without safe_unescape 1');
is_deeply(test_safe_unescape(), $orig, "_safe_unescape without safe_unescape 1");
is_deeply(test_safe_unescape(1), $orig, "_safe_unescape as Path without safe_unescape 1");
is_deeply(make_paths_strings(), $orig, "path_strings as expected toString without safe_unescape 1");
is_deeply(make_paths_strings(1), $orig, "path_strings as expected stringify without safe_unescape 1");
is($path->get_last(), '_2fa_2fb_2fc', 'get_last without safe_unescape 1');
is($path->get_last(1), '_2fa_2fb_2fc', 'get_last trim without safe_unescape 1');

# Trailing slash should be stripped
# Test parent with escaped path
# Test no unneeded {}
set_safe_unescape(qw(/a/b /a/b/{/a/b/c}/e/f/));
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc'), '{/a/b/c}', 'basic _safe_unescape with safe_unescape');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc', 1), '/a/b/c', 'basic _safe_unescape trim with safe_unescape');
is_deeply(test_safe_unescape(), $safe_escaped, "_safe_unescape with safe_unescape");
is_deeply(test_safe_unescape(1), $safe_escaped, "_safe_unescape as Path with safe_unescape");
is_deeply(make_paths_strings(), $orig, "path_strings as expected toString with safe_unescape");
is_deeply(make_paths_strings(1), $safe_escaped, "path_strings as expected stringify with safe_unescape");
is($path->get_last(), '{/a/b/c}', 'get_last with safe_unescape');
is($path->get_last(1), '/a/b/c', 'get_last trim with safe_unescape');

reset_safe_unescape();
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc'), '_2fa_2fb_2fc', 'basic _safe_unescape without safe_unescape 2');
is(EDG::WP4::CCM::Path::_safe_unescape('/a/b', '_2fa_2fb_2fc', 1), '_2fa_2fb_2fc', 'basic _safe_unescape trim without safe_unescape 2');
is_deeply(test_safe_unescape(), $orig, "_safe_unescape without safe_unescape 2");
is_deeply(test_safe_unescape(1), $orig, "_safe_unescape as Path without safe_unescape 2");
is_deeply(make_paths_strings(), $orig, "path_strings as expected toString without safe_unescape 2");
is_deeply(make_paths_strings(1), $orig, "path_strings as expected stringify without safe_unescape 2");
is($path->get_last(), '_2fa_2fb_2fc', 'get_last without safe_unescape 2');
is($path->get_last(1), '_2fa_2fb_2fc', 'get_last trim without safe_unescape 2');

# Test set_safe_unescape without args
reset_safe_unescape();
set_safe_unescape();

is(EDG::WP4::CCM::Path::_safe_unescape($EDG::WP4::CCM::Path::SAFE_UNESCAPE[0]."/", '_2fa_2fb_2fc'),
   '{/a/b/c}', 'set_safe_unescape sets default SAFE_UNESCAPE as safe_unescape list');

reset_safe_unescape();


done_testing();
