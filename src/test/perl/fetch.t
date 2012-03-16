#!/usr/bin/perl
# -*- mode: cperl -*-

=pod

=head1 SYNOPSIS

Script that tests the EDG::WP4::CCM::Fetch module.

=head1 TEST ORGANIZATION

=cut

use strict;
use warnings;
use Test::More tests => 33;
use EDG::WP4::CCM::Fetch;
use Cwd qw(getcwd);
use File::Path qw(make_path remove_tree);
use CAF::Object;

$CAF::Object::NoAction = 1;

sub compile_profile
{
    my ($type) = @_;

    $type ||= 'pan';
    my $filetype = $type eq 'json' ? 'json' : 'xml';
    system("cd src/test/resources && panc -x $type profile.pan && touch -d 0 profile.$filetype");
}

# Removes any existing cache directory from a previous run.
sub cleanup_cache
{
    my ($cache) = @_;

    remove_tree($cache);
}

# Creates a brand new cachedirectory
sub setup_cache
{
    my ($cachedir, $fetch) = @_;

    make_path("$cachedir/data");
    open(my $fh, ">", "$cachedir/data/" . $fetch->EncodeURL($fetch->{PROFILE_URL}));
    close($fh);
    open($fh, ">", "$cachedir/latest.cid");
    print $fh "0\n";
    close($fh);
    open($fh, ">", "$cachedir/current.cid");
    print $fh 0;
    close($fh);
}

compile_profile();

=pod

=head2 Profile retrieval

=head3 Object creation

Ensure a valid object is created

=cut
note("Testing object creation");
my $f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				   CONFIG => 'src/test/resources/ccm.cfg'});
ok($f, "Fetch profile created");
isa_ok($f, "EDG::WP4::CCM::Fetch", "Object is a valid reference");
is($f->{PROFILE_URL}, "https://www.google.com", "Profile URL correctly set");

=pod

=head3 Correct handling of different URLs

The object must be able to handle at least HTTP, HTTPS and file URLs.

Successful retrieves must return a CAF::FileWriter object.

=cut

note("Testing profile retrieval");
my $pf = $f->retrieve($f->{PROFILE_URL}, "target/test/http-output", 0);
ok($pf, "Something got returned");
$pf->cancel();

my $url = sprintf('file://%s/src/test/resources/profile.xml', getcwd());
$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CONFIG => 'src/test/resources/ccm.cfg',
				PROFILE_URL => $url});
is($f->{PROFILE_URL}, $url, "file:// URL accepted");
$pf = $f->retrieve($f->{PROFILE_URL}, "target/test/file-output", 0);
isa_ok($pf, "CAF::FileWriter");
$pf->cancel();


=pod

=head3 Not retrieving anything if the existing files are too new

That is, the C<retrieve> method must set properly the
If-modified-since header, and handle graciously a 304 return code.

=cut

$pf = $f->retrieve($f->{PROFILE_URL}, "target/test/empty", time());
isnt($pf, undef, "No errors found");
is($pf, 0, "Nothing is done if the local file is too new");

=pod

=head3 Honoring the FORCE flag

No matter how recent our cache is, if FORCE is true, the profile will
be downloaded again.

=cut

$f->{FORCE} = 1;
$pf = $f->retrieve($f->{PROFILE_URL}, "target/test/file", time());
isa_ok($pf, "CAF::FileWriter", "The FORCE flag is honored");

=pod

=head3 Error handling

Errors are notified to the calling layer

=cut

$pf = $f->retrieve("http://ljhljhljhljh.78to78t7896.org", "target/test/non-existing", 0);
is($pf, undef, "Error returns undef");

=pod

=head2 Full download process

=head3 Downloading an existing URL works

An existing URL will be downloaded successfully. This means that if
the cache is too recent, we'll receive 0.

=cut

note("Testing profile storage and failovers");
cleanup_cache($f->{CACHE_ROOT});
$f->{FORCE} = 0;
eval { $f->download("profile");};
ok($@, "Cache must exist before calling download");
setup_cache($f->{CACHE_ROOT}, $f);
eval { $pf = $f->download("profile"); };
is($@, "", "Profile was correctly downloaded");

=pod

=head3 Downloading a non-existing URL

A non-existing URL will cause C<undef> to be returned

=cut

$url = $f->{PROFILE_URL};
$f->{PROFILE_URL} = q{http://ljhljkhljho.uioghugkguy.org};
setup_cache($f->{CACHE_ROOT}, $f);
$pf = $f->download("profile");
is($pf, undef, "Non-existing URL with no failover shows an error");

=pod

However, if there is a failover URL, it will be attempted afterwards,
and the function will thus succeed.

=cut

$f->{PROFILE_FAILOVER} = $url;
$pf = $f->download("profile");
isnt($pf, undef, "Non-existing URL with a failover retrieves something");

=pod

=head2 Whatever happens to C<previous> and C<current>?

=cut

note("Testing cache directory manipulation");

my %r = $f->previous();
ok(exists($r{cid}), "cid created");
foreach my $i (qw(cid url profile)) {
    isa_ok($r{$i}, "CAF::FileEditor", "Correct object created for the previous $i");
}
is("$r{cid}", "0\n", "Correct CID read");

%r = $f->current();
foreach my $i (qw(url cid profile)) {
    isa_ok($r{$i}, "CAF::FileWriter", "Correct object created for the current $i");
}
is("$r{cid}", "1\n", "Correct CID will be written");
is("$r{url}", "$f->{PROFILE_URL}\n", "Correct URL for the profile");

=pod

=head2 Parsing

The module must be able to parse XMLDB, Pan and JSON profiles, and to
choose (and invoke) the correct interpreters.

For each format, it must be able to generate a valid cache.

=cut

note("Testing profile parsing and caching");

$f->{FORCE} = 1;
$f->{PROFILE_URL} = $url;
$pf = $f->download("profile");
my ($class, $t) = $f->choose_interpreter("$pf");
ok($t, "XML Pan profile correctly parsed");
is($class, 'EDG::WP4::CCM::XMLPanProfile', "Pan XML profile correctly diagnosed");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");
compile_profile("xmldb");
setup_cache($f->{CACHE_ROOT}, $f);
$pf = $f->download("profile");
($class, $t) = $f->choose_interpreter("$pf");
ok($t, "XMLDB profile correctly parsed");
is($class, 'EDG::WP4::CCM::XMLDBProfile', "XMLDB profile correctly diagnosed");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");
compile_profile("json");
$f->{PROFILE_URL} =~ s{xml}{json};
setup_cache($f->{CACHE_ROOT}, $f);
$pf = $f->download("profile");
($class, $t) = $f->choose_interpreter("$pf");
ok($t, "JSON profile correctly parsed");
is($class, 'EDG::WP4::CCM::JSONProfile', "JSON profile correctly diagnosed");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");

=pod

=head2 Generate a correct cache database

=cut

