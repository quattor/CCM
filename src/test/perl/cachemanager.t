#!/usr/bin/perl -w

#
# cache CacheManager.pm test script
#

#
# TODO: test default path in the call CacheManager -> new ()
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok make_file);
use LC::Exception qw(SUCCESS);
use LC::File qw (differ);
use CAF::FileWriter;
use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
				      $CURRENT_CID_FN $LATEST_CID_FN
                      $PROFILE_DIR_N);
use Test::MockModule;

use Cwd;

# check exported readonly
is($DATA_DN, "data", "DATA_DN exported and expected value");
is($GLOBAL_LOCK_FN, "global.lock", "GLOBAL_LOCK_FN exported and expected value");
is($CURRENT_CID_FN, "current.cid", "CURRENT_CID_FN exported and expected value");
is($LATEST_CID_FN, "latest.cid", "LATEST_CID_FN exported and expected value");
is($PROFILE_DIR_N, "profile.", "PROFILE_DIR_N exported and expected value");


my $ec = LC::Exception::Context->new->will_store_errors;
my $cptmp = getcwd()."/target/tmp";
my $cp = "$cptmp/cm-test";

mkdir($cptmp) if (! -d $cptmp);

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"),
     "EDG::WP4::CCM::CacheManager->new (foo)");

#create dir and file structure

ok(! -d $cp, "cache manager test dir $cp does not yet exist.");

eok ($ec, EDG::WP4::CCM::CacheManager::_check_type("directory", $cp, $cp),
     "CacheManager::_check_type(directory, $cp)");

mkdir($cp);
ok(-d $cp, "cache manager test dir $cp exists.");

ok (EDG::WP4::CCM::CacheManager::_check_type("directory", $cp, $cp),
     "CacheManager::_check_type(directory, $cp)");

mkdir("$cp/$DATA_DN");

my $ccidfn = "$cp/$CURRENT_CID_FN";
my $lcidfn = "$cp/$LATEST_CID_FN";

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"),
     "EDG::WP4::CCM::CacheManager->new (foo)");

make_file("$cp/$GLOBAL_LOCK_FN", "no\n");

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"),
     "EDG::WP4::CCM::CacheManager->new (foo)");

make_file($ccidfn, "1\n");

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"),
     "EDG::WP4::CCM::CacheManager->new (foo)");

eok ($ec, EDG::WP4::CCM::CacheManager::_check_type("file", $lcidfn, $lcidfn),
     "EDG::WP4::CCM::CacheManager::_check_type(file, $lcidfn, $lcidfn)");

make_file($lcidfn, "1\n");

ok (EDG::WP4::CCM::CacheManager::_check_type("file", $lcidfn, $lcidfn),
     "EDG::WP4::CCM::CacheManager::_check_type(file, $lcidfn, $lcidfn)");

my $cm;

ok ($cm = EDG::WP4::CCM::CacheManager->new ($cp),
     "EDG::WP4::CCM::CacheManager->new ($cp)");

is ($cm->isLocked(), 0, '$cm->isLocked() false');

make_file("$cp/$GLOBAL_LOCK_FN", "yes\n");

is ($cm->isLocked(), 1, '$cm->isLocked() true');

make_file("$cp/$GLOBAL_LOCK_FN", "foo\n");

eok ($ec, $cm->isLocked(), '$cm->isLocked() throws exception');

make_file("$cp/$GLOBAL_LOCK_FN", "no\n");

make_file("$cp/test_yes", "yes\n");
make_file("$cp/test_no", "no\n");

my $ccidfh = CAF::FileWriter->new($ccidfn);
print $ccidfh "1\n";
$ccidfh->close();

my $lcidfh = CAF::FileWriter->new($lcidfn);
print $lcidfh "2\n";
$lcidfh->close();

is ($cm->getCurrentCid(), 1, '$cm->getCurrentCid() == 2');
is ($cm->getLatestCid(), 2, '$cm->getLatestCid() == 2');

#old unlock test
#  implied set_ccid_to_lcid
make_file("$cp/$GLOBAL_LOCK_FN", "no\n");

$lcidfh = CAF::FileReader->new($lcidfn);
chop($lcidfh);
$ccidfh = CAF::FileWriter->new($ccidfn);
print $ccidfh "$lcidfh\n";
$ccidfh->close();

is ($cm->isLocked(), 0, '$cm->isLocked() false');
is ($cm->getCurrentCid(), 2, '$cm->getCurrentCid() == 2');
is ($cm->getLatestCid(), 2, '$cm->getLatestCid() == 2');

eok ($ec, $cm->getLockedConfiguration (0), '$cm->getLockedConfiguration (0)');

mkdir("$cp/profile.1");
mkdir("$cp/profile.2");
ok(-d "$cp/profile.1", "cache manager profile.1 dir exists.");
ok(-d "$cp/profile.2", "cache manager profile.2 dir exists.");

is_deeply($cm->getCids(), [1, 2], "getCids returns expected sorted list of cids");

my ($cfg, $pidfile);
ok ($cfg = $cm->getAnonymousConfiguration (0), '$cm->getAnonymousConfiguration (0)');
ok ($cfg->getConfigurationId() == 2, '$cfg -> getConfigurationId() == 2');
is ($cfg->isLocked(), 0, '$cfg->isLocked() false');
# no pid file should exist
$pidfile = $cfg->_pid_filename();
ok( ! -f $pidfile, "pid file $pidfile does not exist with anonymous configuration");

ok ($cfg = $cm->getLockedConfiguration (0), '$cm->getLockedConfiguration (0)');
ok ($cfg->getConfigurationId() == 2, '$cfg -> getConfigurationId() == 2');
is ($cfg->isLocked(), 1, '$cfg->isLocked() true');
# pid file should exist
$pidfile = $cfg->_pid_filename();
ok(-f $pidfile, "pidfile $pidfile exists with locked configuration");

ok ($cfg = $cm->getLockedConfiguration (0,1), '$cm->getLockedConfiguration (0,1)');
ok ($cfg->getConfigurationId() == 1, '$cfg -> getConfigurationId() == 1');
is ($cfg->isLocked(), 1, '$cfg->isLocked() true');

ok ($cfg = $cm->getUnlockedConfiguration (0), '$cm->getUnlockedConfiguration (0)');
ok ($cfg->getConfigurationId() == 2, '$cfg -> getConfigurationId() == 2');
is ($cfg->isLocked(), 0, '$cfg->isLocked() false');

ok ($cfg = $cm->getUnlockedConfiguration (0,1), '$cm->getUnlockedConfiguration (0,1)');
ok ($cfg->getConfigurationId() == 2, '$cfg -> getConfigurationId() == 2');
is ($cfg->isLocked(), 0, '$cfg->isLocked() false');

mkdir("$cp/profile.3");
mkdir("$cp/profile.4");
ok(-d "$cp/profile.3", "cache manager profile.3 dir exists.");
ok(-d "$cp/profile.4", "cache manager profile.4 dir exists.");

is_deeply($cm->getCids(), [1, 2, 3 ,4], "getCids returns expected sorted list of cids");

is ($cm->getCurrentCid(), 2, '$cm->getCurrentCid() == 2 (unmodified)');
is ($cm->getLatestCid(), 2, '$cm->getLatestCid() == 2 (unmodified)');

# current = 3; latest = 4
$ccidfh = CAF::FileWriter->new($ccidfn);
print $ccidfh "3\n";
$ccidfh->close();

$lcidfh = CAF::FileWriter->new($lcidfn);
print $lcidfh "4\n";
$lcidfh->close();

my $ccid = $cm->getCurrentCid();
my $lcid = $cm->getLatestCid();
is ($ccid, 3, '$cm->getCurrentCid() == 3');
is ($lcid, 4, '$cm->getLatestCid() == 4');
# important for getCid tests to distinguish results)
ok($ccid != $lcid, "Current CID is not equal to latest CID");

# most recent 6
# is a directory without updating latest (should not happen in real)
my $mcid = 6;
mkdir("$cp/profile.$mcid");
ok(-d "$cp/profile.$mcid", "cache manager profile.6 dir exists.");

is_deeply($cm->getCids(), [1, 2, 3 ,4, 6], "getCids returns expected sorted list of cids");

# test getCid method
is($cm->getCid(), $ccid, "getCid returns current CID with no arg (=undef)");
is($cm->getCid(undef), $ccid, "getCid returns current CID with undef");
is($cm->getCid(''), $ccid, "getCid returns current CID with empty string");
is($cm->getCid('current'), $ccid, "getCid returns current CID with 'current' string");

is($cm->getCid('latest'), $lcid, "getCid returns latest CID with 'latest' string");
is($cm->getCid('-'), $lcid, "getCid returns latest CID with '-' string");

is($cm->getCid(1), 1, "getCid returns CID=1 with arg 1");
is($cm->getCid(7), undef, "getCid returns undef with arg 7 (non-existing CID)");
is($cm->getCid("woohoo"), undef, "getCid returns undef with arg woohoo (non-existing CID)");

is($cm->getCid(-1), $mcid, "getCid returns most recent with arg -1");
# not really $mcid-2, but there happens to be a gap (5 is missing)
is($cm->getCid(-2), $mcid-2, "getCid returns 2nd most recent with arg -2");

is($cm->getCid(-6), undef, "getCid returns undef with arg -6 (there's no 6th most recent CID)");

#$cm->lock();
make_file("$cp/$GLOBAL_LOCK_FN", "yes\n");
ok ($cfg = $cm->_getConfig (0, 0), '$cfg->_getConfig (0, 0)');
is ($cfg->getConfigurationId(), 3, '$cfg->getConfigurationId() == 3');

#$cm->unlock();
# also sets current.cid to latest.cid
make_file("$cp/$GLOBAL_LOCK_FN", "no\n");
$lcidfh = CAF::FileReader->new($lcidfn);
chop($lcidfh);
$ccidfh = CAF::FileWriter->new($ccidfn);
print $ccidfh "$lcidfh\n";
$ccidfh->close();

ok ($cfg = $cm->_getConfig (0, 0), '$cfg->_getConfig (0, 0)');
is ($cfg->getConfigurationId(), 4, '$cfg->getConfigurationId() == 4');

$ccidfh = CAF::FileReader->new($ccidfn);
chop($ccidfh);
$lcidfh = CAF::FileReader->new($lcidfn);
chop($lcidfh);
ok ("$lcidfh" == 4 && "$ccidfh" == 4,
    "current.cid == 4 && latest.cid == 4");

make_file("$cp/td.txt", "1\n");
my $url = "file:///$cp/td.txt";

# Test the getConfiguration method by checking the arguments
mkdir("$cp/profile.5");
ok(-d "$cp/profile.5", "cache manager profile.5 dir exists.");
$lcidfh = CAF::FileWriter->new($lcidfn);
print $lcidfh "5\n";
$lcidfh->close();

# passed to _getConfig
my $args_getConfig;
my $cred; # does nothing

# update it to current current CID
$ccid = $cm->getCurrentCid();
$lcid = $cm->getLatestCid();
is ($ccid, 4, '$cm->getCurrentCid() == 4');
is ($lcid, 5, '$cm->getLatestCid() == 5');

my $mock = Test::MockModule->new('EDG::WP4::CCM::CacheManager');
$mock->mock('_getConfig', sub {
    shift;
    $args_getConfig = \@_;
    return 1;
});

$cm->getConfiguration($cred);
is_deeply($args_getConfig, [0, $cred, $ccid, -1],
          "expected arguments for undefined cid");

$cm->getConfiguration($cred, 2);
is_deeply($args_getConfig, [1, $cred, 2, -1],
          "expected arguments for defined cid");

$cm->getConfiguration($cred, -1);
is_deeply($args_getConfig, [1, $cred, $mcid, -1],
          "expected arguments for cid == -1");

$cm->getConfiguration($cred, undef, locked => 1, anonymous => 1);
is_deeply($args_getConfig, [1, $cred, $ccid, 1],
          "expected arguments for undefined cid with forced locked and anonymous");

$cm->getConfiguration($cred, 2, locked => 0, anonymous => 1);
is_deeply($args_getConfig, [0, $cred, 2, 1],
          "expected arguments for defined cid with forced locked and anonymous");

# cid == -1 gets resolved to most recent via getCid
$cm->getConfiguration($cred, -1, locked => 0, anonymous => 0, name_template => 'testname');
is_deeply($args_getConfig, [0, $cred, $mcid, 0, 'name_template', 'testname'],
          "expected arguments for cid == -1 with forced locked and anonymous and name template testname");


$mock->unmock('_getConfig');


done_testing();
