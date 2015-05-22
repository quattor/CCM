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
use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
				      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::SyncFile qw ();
use Test::MockModule;

use Cwd;

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

my $ccidf;
ok ($ccidf = EDG::WP4::CCM::SyncFile->new("$ccidfn"),
    "SyncFile->new($ccidf)");
my $lcidf;
ok ($lcidf = EDG::WP4::CCM::SyncFile->new("$lcidfn"),
    "SyncFile->new($cp/$lcidfn)");

$ccidf->write ("1");
$lcidf->write ("2");

#old unlock test
#  implied set_ccid_to_lcid
make_file("$cp/$GLOBAL_LOCK_FN", "no\n");
$ccidf->write ($lcidf->read());

is ($cm->isLocked(), 0, '$cm->isLocked() false');
is ($cm->getCurrentCid(), 2, '$cm->getCurrentCid() == 2');

eok ($ec, $cm->getLockedConfiguration (0), '$cm->getLockedConfiguration (0)');

mkdir("$cp/profile.1");
mkdir("$cp/profile.2");
ok(-d "$cp/profile.1", "cache manager profile.1 dir exists.");
ok(-d "$cp/profile.2", "cache manager profile.2 dir exists.");

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

# current = 3; latest = 4
$ccidf->write ("3");
$lcidf->write ("4");

#$cm->lock();
make_file("$cp/$GLOBAL_LOCK_FN", "yes\n");
ok ($cfg = $cm->_getConfig (0, 0), '$cfg->_getConfig (0, 0)');
is ($cfg->getConfigurationId(), 3, '$cfg->getConfigurationId() == 3');

#$cm->unlock();
# also sets current.cid to latest.cid
make_file("$cp/$GLOBAL_LOCK_FN", "no\n");
$ccidf->write ($lcidf->read());

ok ($cfg = $cm->_getConfig (0, 0), '$cfg->_getConfig (0, 0)');
is ($cfg->getConfigurationId(), 4, '$cfg->getConfigurationId() == 4');
ok ($lcidf->read() == 4 && $ccidf->read() == 4,
    "current.cid == 4 && latest.cid == 4");

make_file("$cp/td.txt", "1\n");
my $url = "file:///$cp/td.txt";

# Test the getConfiguration method by checking the arguments
# passed to _getConfig
my $args_getConfig;
my $cred; # does nothing

my $mock = Test::MockModule->new('EDG::WP4::CCM::CacheManager');
$mock->mock('_getConfig', sub {
    shift;
    $args_getConfig = \@_;
    return 1;
});

$cm->getConfiguration($cred);
is_deeply($args_getConfig, [0, $cred, undef, -1],
          "expected arguments for undefined cid");

$cm->getConfiguration($cred, 2);
is_deeply($args_getConfig, [1, $cred, 2, -1],
          "expected arguments for defined cid");

$cm->getConfiguration($cred, -1);
is_deeply($args_getConfig, [1, $cred, undef, -1],
          "expected arguments for cid == -1");

$cm->getConfiguration($cred, undef, locked => 1, anonymous => 1);
is_deeply($args_getConfig, [1, $cred, undef, 1],
          "expected arguments for undefined cid with forced locked and anonymous");

$cm->getConfiguration($cred, 2, locked => 0, anonymous => 1);
is_deeply($args_getConfig, [0, $cred, 2, 1],
          "expected arguments for defined cid with forced locked and anonymous");

# cid == -1 always resets the cid to undef
$cm->getConfiguration($cred, -1, locked => 0, anonymous => 0);
is_deeply($args_getConfig, [0, $cred, undef, 0],
          "expected arguments for cid == -1 with forced locked and anonymous");


$mock->unmock('_getConfig');


done_testing();
