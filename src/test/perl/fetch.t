#!/usr/bin/perl
# -*- mode: cperl -*-

=pod

=head1 SYNOPSIS

Script that tests the EDG::WP4::CCM::Fetch module.

=head1 TEST ORGANIZATION

=cut

use strict;
use warnings;
use Test::More;
use EDG::WP4::CCM::Fetch qw($GLOBAL_LOCK_FN $FETCH_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN
    $TABCOMPLETION_FN
    NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

use EDG::WP4::CCM::CacheManager::Configuration;
use Cwd qw(getcwd);
use File::Path qw(mkpath rmtree);
use CAF::Object qw(SUCCESS CHANGED);
use Carp qw(croak);
use CAF::Reporter;

use Test::Quattor::TextRender::Base;
use Test::Quattor::Object;
use Test::MockModule;

my $obj = Test::Quattor::Object->new();

my $mock_hr = Test::MockModule->new('HTTP::Response');
my $mock_d = Test::MockModule->new('EDG::WP4::CCM::Fetch::Download');

my $mock_f = Test::MockModule->new('EDG::WP4::CCM::Fetch');
foreach my $rep (qw(info debug verbose warn error)) {
  $mock_f->mock($rep, sub {shift; $obj->$rep(@_);});
}

my $caf_trd = mock_textrender();

#$CAF::Object::NoAction = 1;

# Test the exported constants
is($GLOBAL_LOCK_FN, "global.lock", "Exported GLOBAL_LOCK_FN");
is($FETCH_LOCK_FN, "fetch.lock", "Exported FETCH_LOCK_FN");
is($CURRENT_CID_FN, "current.cid", "Exported CURRENT_CID_FN");
is($LATEST_CID_FN, "latest.cid", "Exported LATEST_CID_FN");
is($DATA_DN, "data", "Exported DATA_DN");
is($TABCOMPLETION_FN, "tabcompletion", "Exported TABCOMPLETION_FN");

# These come from EDG::WP4::CCM::Fetch::Config, but are still exported via Fetch
is(NOQUATTOR, "/etc/noquattor", "Exported NOQUATTOR");
is(NOQUATTOR_EXITCODE, "3", "Exported NOQUATTOR_EXITCODE");
is(NOQUATTOR_FORCE, "force-quattor", "Exported NOQUATTOR_FORCE");

sub compile_profile
{
    my ($type) = @_;

    $type ||= 'pan';

    my $filetype = $type eq 'json' ? 'json' : 'xml';
    mkpath("target/test/fetch");
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

    rmtree($cache);
}

# Creates a brand new cachedirectory
sub setup_cache
{
    my ($cachedir, $fetch) = @_;

    mkpath("$cachedir/data");
}

compile_profile();

my $mock_profcache = Test::MockModule->new('EDG::WP4::CCM::Fetch::ProfileCache');

my $getpermissions;
$mock_profcache->mock('GetPermissions', sub {
    my @args = @_;
    $getpermissions = \@_;
    my $orig = $mock_profcache->original('GetPermissions');
    # Ignore all group/world _readables
    return &$orig();
});

my $setmask;
$mock_profcache->mock('SetMask', sub {
    my @args = @_;
    $setmask = \@_;
    my $orig = $mock_profcache->original('SetMask');
    return &$orig(@args);
});

my $make_cacheroot;
$mock_profcache->mock('MakeCacheRoot', sub {
    my @args = @_;
    $make_cacheroot = \@_;
    my $orig = $mock_profcache->original('MakeCacheRoot');
    return &$orig(@args);
});

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

$f = EDG::WP4::CCM::Fetch->new({CONFIG => 'src/test/resources/ccm_tabcompletion.cfg'});
is($f->{TABCOMPLETION}, 1, "TABCOMPLETION set via config file");

$f = EDG::WP4::CCM::Fetch->new({
                               CONFIG => 'src/test/resources/ccm_tabcompletion.cfg',
                               TABCOMPLETION => 0,
                              });
is($f->{TABCOMPLETION}, 0, "TABCOMPLETION set via new (in uppercase) precedes value in config file");


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


$getpermissions = [];
$f = EDG::WP4::CCM::Fetch->new({
    FOREIGN => 0,
    CONFIG => 'src/test/resources/ccm.cfg',
    GROUP_READABLE => 'mygroup',
    WORLD_READABLE => 1,
});
ok($f, "Fetch profile created");
isa_ok($f, "EDG::WP4::CCM::Fetch", "Object is a valid reference");
is($f->{PROFILE_URL}, "https://www.google.com", "Profile URL correctly set");

is_deeply($getpermissions, [$f, "mygroup", 1],
          "new calls GetPermissions as expected");
is_deeply($f->{permission}, {
    directory => {mode => 0700},
    file => {log => $f, mode => 0600},
    mask => 077,
}, "permission attribute is added (with mocked values)");

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
# mtime is 0, safe to assume that the google homepage is more recent than that
my $pf = $f->retrieve($f->{PROFILE_URL}, "target/test/http-output", 0);
if (defined($pf)) {
  isa_ok($pf, "CAF::FileReader", "FileReader returned on success and change");
} else {
  # only encoding errors are "ok" here. see https://github.com/quattor/CCM/issues/158
  like($obj->{LOGLATEST}->{ERROR} || "no error logged",
       qr{Failed to decode content .* does not map to Unicode},
       "undef reply from google is only ok if it's some encoding issue");
}

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
isa_ok($pf, "CAF::FileReader");
$pf->cancel();

unlink("target/test/profile");
unlink("target/test/profile.xml");
compile_profile("pan.gz");
$pf = $f->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
isa_ok($pf, "CAF::FileReader");
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
isa_ok($pf, "CAF::FileReader", "The FORCE flag is honored");

=pod

=head3 Error handling

Errors are notified to the calling layer

=cut

$pf = $f->retrieve("http://ljhljhljhljh.78to78t7896.org", "target/test/non-existing", 0);
is($pf, undef, "Error returns undef");


=head3 trust

=cut


$mock_hr->mock('content_encoding', 'krbencrypt');

# return regular decoded content, it's not encrypted anyway
my $decrypt = 0;
my $author = 'AUTHOR/the.server@EXAMPLE.COM';
$mock_d->mock('_gss_decrypt', sub {$decrypt = 1; shift; return ($author, shift); });


is_deeply($f->{TRUST}, [], "By default TRUST attr is empty hashref");

$pf = undef;
local $@;
eval {
    $pf = $f->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
};
ok(! defined($pf), "empty trust fails, retrieve doesn't return");
ok($decrypt, "_gss_decrypt called");
like("$@", qr{^Refusing profile generated by AUTHOR/the.server\@EXAMPLE.COM }, "retrieve die'ed as expected with empty trusts");

# reset
$@ = "";

$pf = undef;
$decrypt = 0;
$f->{TRUST} = [qw(SOMETHING NO_MATCH)];
eval {
    $pf = $f->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
};
ok(! defined($pf), "wrong trusts fails, retrieve doesn't return");
ok($decrypt, "_gss_decrypt called");
like("$@", qr{^Refusing profile generated by AUTHOR/the.server\@EXAMPLE.COM }, "retrieve die'ed as expected with wrong trusts");

# reset
$@ = "";

$pf = undef;
$decrypt = 0;
$f->{TRUST} = [qw(SOMETHING NO_MATCH AUTHOR/the.server@EXAMPLE.COM)];
$pf = $f->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
isa_ok($pf, 'CAF::FileReader', "matching trust ok, retrieve returns FileReader");
ok($decrypt, "_gss_decrypt called on matching trust");
is("$@", "", "No eval exception set");
$pf->cancel() if defined($pf);

my $f_trust = EDG::WP4::CCM::Fetch->new({
    FOREIGN => 0,
    CONFIG => 'src/test/resources/ccm_trust.cfg',
    GROUP_READABLE => 'mygroup',
    WORLD_READABLE => 1,
});
ok($f_trust, "Fetch trust profile created");
isa_ok($f_trust, "EDG::WP4::CCM::Fetch", "Object is a valid reference for trust config");
is_deeply($f_trust->{TRUST}, [qw(SOMETHING NO_MATCH all.lower.domain@all.lower.realm AUTHOR/the.server@EXAMPLE.COM)],
          "trust from config file");
$pf = undef;
$decrypt = 0;
$author = 'all.lower.domain@all.lower.realm';
$pf = $f_trust->retrieve("$f->{PROFILE_URL}", "target/test-file-output", 0);
isa_ok($pf, 'CAF::FileReader', "matching alllower trust ok, retrieve returns FileReader");
ok($decrypt, "_gss_decrypt called on matching alllower trust");
is("$@", "", "No eval exception set for alllower");
$pf->cancel() if defined($pf);


# unmock
$mock_hr->unmock('content_encoding');
$mock_d->unmock('_gss_decrypt');
# reset
$f->{TRUST} = [];

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

Multiple comma seperated failover URLs are supported. Try two failovers,
the first of which doesn't work.

=cut

$f->{PROFILE_FAILOVER} = "http://afjbsabfaf.fadsfsagfsagagf.org,$url";
$pf = $f->download("profile");
isnt($pf, undef, "Non-existing URL with a non-existing first failover retrieves something");

=pod

=head2 Whatever happens to C<previous> and C<current>?

=cut

note("Testing cache directory manipulation");
$f->{FORCE} = 1;
$pf = $f->download("profile");
isa_ok($pf, "CAF::FileReader", "download retruns CAF::FileReader instance");

my %r = $f->previous();
like(*{$r{url}}->{filename}, qr{profile.url$},
     'Correct file read for the previous URL');
like(*{$r{profile}}->{filename}, qr{profile$},
     "Correct file read with the previous XML");
ok(exists($r{cid}), "cid created");
foreach my $i (qw(cid url profile)) {
    isa_ok($r{$i}, "CAF::FileEditor", "Correct object created for the previous $i");
}


is("$r{cid}", "0\n", "Correct CID read");

$setmask = [];
$make_cacheroot = [];
%r = $f->current($pf, %r);
foreach my $i (qw(url cid profile)) {
    isa_ok($r{$i}, "CAF::FileWriter", "Correct object created for the current $i");
  }
# cache_root from test/resources/ccm.conf
is_deeply($setmask, [$f, 077, undef], "current calls SetMask as expected after mocking");
is_deeply($make_cacheroot, [$f, "target/test/cache", {mode => 0700 }, "profile.1"],
          "current calls MakeCacheRoot as expected after mocking");
like("$r{profile}", qr{^<\?xml}, "Current profile will be written");
is("$r{cid}", "1\n", "Correct CID will be written");
is("$r{url}", "$f->{PROFILE_URL}\n", "Correct URL for the profile");

my $legacy_profile_name = *{$r{profile}}->{filename}.".xml";
ok(-l $legacy_profile_name, "$legacy_profile_name is a symlink");

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
is($class, 'EDG::WP4::CCM::Fetch::XMLPanProfile', "Pan XML profile correctly diagnosed");
is(ref($t), "ARRAY", "XML Pan profile is not empty");
is($t->[0], 'nlist', "XML Pan profile looks correct");
is ($f->process_profile("$pf", %r), 1,
    "Cache from a Pan profile correctly created");

setup_cache($f->{CACHE_ROOT}, $f);
compile_profile("json");
$f->{PROFILE_URL} =~ s{xml}{json}g;
$pf = $f->download("profile");
($class, $t) = $f->choose_interpreter("$pf");
ok($t, "JSON profile correctly parsed");
is($class, 'EDG::WP4::CCM::Fetch::JSONProfileTyped', "JSON profile correctly diagnosed");
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

# At this point, the profile is defined as a JSON profile...
# First download the profile to be sure that it is already there
# before the test.
is($f->fetchProfile(), CHANGED, "Initial fetchProfile worked correctly (JSON profile)");
$f->{FORCE} = 0;
is($f->fetchProfile(), SUCCESS, "fetchProfile of the same JSON profile succeeded");
is($f->{FORCE}, 0, "And the FORCE flag was not modified 1");

=pod

=item * To B<set> the C<FORCE> flag when downloading from a different URL

=cut

$f->{PROFILE_URL} =~ s{json}{xml};
$f->{FORCE} = 0;
$f->setup_reporter(0, 0, 1);
is($f->fetchProfile(), CHANGED, "fetchProfile worked correctly on XML profile");
is($f->{FORCE}, 1, "A change in the URL forces to re-download");
# Check that FORCE flag is also respected/not modified with XML profile in case of
# format-specific issue.
$f->{FORCE} = 0;
is($f->fetchProfile(), SUCCESS, "fetchProfile worked correctly on the same XML profile");
is($f->{FORCE}, 0, "And the FORCE flag was not modified 2");

=pod

=head2 Test tabcompletion generation

=cut

is($f->{TABCOMPLETION}, 0, "tabcompletion generation off");

$f->{FORCE} = 1;
$f->{TABCOMPLETION} = 1;
is($f->fetchProfile(), CHANGED,
   "fetchProfile worked correctly on the same XML profile (with force and tabcompletion enabled)");

my %latest = $f->previous();

my $tab_fn = "$latest{dir}/$TABCOMPLETION_FN";
ok(-f $tab_fn, "tabcompletion file found");
my $tab_fh = CAF::FileReader->new($tab_fn);
my $tab_txt = "$tab_fh";
$tab_txt =~ s/\s//g; # squash whitespace
is($tab_txt,
   "//a//a/0/a/1/a/2/b/c/d/e//e/f/g//g/0//g/0/0/g/0/1/g/1//g/1/0/g/1/1/h//h/0//h/0/a/h/0/b/h/1//h/1/a",
   "Expected content of tabcompletion file found");

$f->{TABCOMPLETION} = 0;
$f->{FORCE} = 0;

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


done_testing();
