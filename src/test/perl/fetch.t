#!/usr/bin/perl
# -*- mode: cperl -*-

=pod

=head1 SYNOPSIS

Script that tests the EDG::WP4::CCM::Fetch module.

=head1 TEST ORGANIZATION

=cut

use strict;
use warnings;
use Test::More tests => 46;
use EDG::WP4::CCM::Fetch;
use EDG::WP4::CCM::Configuration;
use Cwd qw(getcwd);
use File::Path qw(make_path remove_tree);
use CAF::Object;
use Carp qw(croak);
use CAF::Reporter;
use LC::Exception qw(SUCCESS);


#$CAF::Object::NoAction = 1;

sub compile_profile
{
    my ($type) = @_;

    $type ||= 'pan';

    my $filetype = $type eq 'json' ? 'json' : 'xml';
    make_path("target/test/fetch");
    system (qq{cd src/test/resources &&
               panc --formats $type --output-dir ../../../target/test/fetch/ profile.pan &&
               touch -d 0 ../../../target/test/fetch/profile.$filetype});
    croak ("Couldn't compile profile of type $type") if $?;
    croak ("WTF?") if ! -f "target/test/fetch/profile.$filetype";
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
    # open(my $fh, ">", "$cachedir/global.lock");
    # print $fh "no\n";
}

compile_profile();

=pod

=head2 Profile retrieval

=head3 Object creation

Ensure a valid object is created. Including, for backwards
compatibility, when C<PROFILE> is given. C<PROFILE_URL> has higher
priority, though.

=cut
note("Testing object creation");

my $f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				   CONFIG => 'src/test/resources/ccm.cfg',
				   PROFILE => "file://foo/bar"});
is($f->{PROFILE_URL}, "file://foo/bar", "PROFILE parameter honored");
$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CONFIG => 'src/test/resources/ccm.cfg',
				PROFILE => "file://foo/bar",
				PROFILE_URL => "file://baz"});
is($f->{PROFILE_URL}, "file://baz", "PROFILE_URL has priority over old PROFILE");

$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CACHE_ROOT => "/foo/bar",
				CONFIG => 'src/test/resources/ccm.cfg'});
is($f->{CACHE_ROOT}, "/foo/bar",
   "Cache root given to constructor overrides config file");
$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CONFIG => 'src/test/resources/ccm.cfg'});
ok($f, "Fetch profile created");
isa_ok($f, "EDG::WP4::CCM::Fetch", "Object is a valid reference");
is($f->{PROFILE_URL}, "https://www.google.com", "Profile URL correctly set");



=pod



=cut


=pod

=head3 Correct handling of different URLs

The object must be able to handle at least HTTP, HTTPS and file URLs.

Successful retrieves must return a CAF::FileWriter object.

=cut

# in case the LWP::Protocol::https can't be loaded/found, 
# the following test fails with
#   Got an unexpected result while retrieving https://www.google.com: 501 
#   Protocol scheme 'https' is not supported (LWP::Protocol::https not installed)
# explicit import to generate a clean error
# It will also fail if Net::SSL is not installed 
# (part of package that provides perl(Crypt::SSLeay))
# These are the requires as listed in the pom.xml file.
use Crypt::SSLeay;
use LWP::Protocol::https;

note("Testing profile retrieval");
my $pf = $f->retrieve($f->{PROFILE_URL}, "target/test/http-output", 0);
ok($pf, "Something got returned");
$pf->cancel();

my $specialchars = "http://securedserver?parameter1=foo&parameter=foo%20bar";
$f->setProfileURL($specialchars);
is($f->{PROFILE_URL}, $specialchars, "Can use http URLs with parameters");

compile_profile();

my $url = sprintf('file://%s/target/test/fetch/profile.xml', getcwd());
$f = EDG::WP4::CCM::Fetch->new({FOREIGN => 0,
				CONFIG => 'src/test/resources/ccm.cfg',
				PROFILE_URL => $url});
is($f->{PROFILE_URL}, $url, "file:// URL accepted");
$pf = $f->retrieve($f->{PROFILE_URL}, "target/test/file-output", 0);
isa_ok($pf, "CAF::FileWriter");
$pf->cancel();

unlink("target/test/profile.xml");
compile_profile("pan.gz");
$pf = $f->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
isa_ok($pf, "CAF::FileWriter");
is(substr("$pf", 0, 1), "<", "Automatically decompressed");

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
$f->{FORCE} = 1;
$pf = $f->download("profile");
my %r = $f->previous();
like(*{$r{url}}->{filename}, qr{profile.url$},
     'Correct file read for the previous URL');
like(*{$r{profile}}->{filename}, qr{profile.xml$},
     "Correct file read with the previous XML");
ok(exists($r{cid}), "cid created");
foreach my $i (qw(cid url profile)) {
    isa_ok($r{$i}, "CAF::FileEditor", "Correct object created for the previous $i");
}


is("$r{cid}", "0\n", "Correct CID read");


%r = $f->current($pf, %r);
foreach my $i (qw(url cid profile)) {
    isa_ok($r{$i}, "CAF::FileWriter", "Correct object created for the current $i");
}
like("$r{profile}", qr{^<\?xml}, "Current profile will be written");
is("$r{cid}", "1\n", "Correct CID will be written");
is("$r{url}", "$f->{PROFILE_URL}\n", "Correct URL for the profile");

=pod

=head2 Parsing

The module must be able to parse Pan and JSON profiles, and to
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
is(ref($t), "ARRAY", "XML Pan profile is not empty");
is($t->[0], 'nlist', "XML Pan profile looks correct");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");
setup_cache($f->{CACHE_ROOT}, $f);
setup_cache($f->{CACHE_ROOT}, $f);
compile_profile("json");
$f->{PROFILE_URL} =~ s{xml}{json}g;
$pf = $f->download("profile");
($class, $t) = $f->choose_interpreter("$pf");
ok($t, "JSON profile correctly parsed");
is($class, 'EDG::WP4::CCM::JSONProfile', "JSON profile correctly diagnosed");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");


=pod

=head2 Test all methods together

If all goes well, we can test the C<fetchProfile> method, which the
only really public method for this module.

We expect it:

=over

=item * To respect the C<FORCE> flag when downloading from the same URL

=cut


$f->{FORCE} = 0;
system("cat target/test/cache/profile.*/profile.url");
is($f->fetchProfile(), SUCCESS, "Full fetchProfile worked correctly");
is($f->{FORCE}, 1, "And the FORCE flag was not modified");
$f->{PROFILE_URL} =~ s{json}{xml};

=pod

=item * To B<set> the C<FORCE> flag when downloading from a different URL

=cut

$f->{FORCE} = 0;
$f->setup_reporter(0, 0, 1);
is($f->fetchProfile(), SUCCESS, "fetchProfile worked correctly on JSON profile");
is($f->{FORCE}, 1, "A change in the URL forces to re-download");


=pod

=item * To return something special in the event of a network error

=cut

$f->{PROFILE_URL} = "http://uhlughliuhilhl.uyiuhkuh.net";
delete($f->{PROFILE_FAILOVER});
is($f->fetchProfile(), undef, "Network errors are correctly diagnosed");

=pod

=head2 Ensure the cache database is correct

=cut

%r = ();

my $cm = EDG::WP4::CCM::CacheManager->new($f->{CACHE_ROOT});
my $cfg = $cm->getUnlockedConfiguration() or die "Mierda";
ok($cfg->elementExists("/"), "There is a root element in the cache");
