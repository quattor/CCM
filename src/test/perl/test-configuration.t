#
# cache Configuration.pm test script
#

use strict;
use warnings;

use POSIX qw (getpid);
use Test::More;
use myTest qw (eok make_file);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN 
				      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use Cwd;

my $ec = LC::Exception::Context->new->will_store_errors;

my $cptmp = getcwd()."/target/tmp";
my $cp = "$cptmp/cm-test";

my $ccidfn = "$cp/$CURRENT_CID_FN";
my $lcidfn = "$cp/$LATEST_CID_FN";


mkdir($cptmp) if (! -d $cptmp);
mkdir($cp);
ok(-d $cp, "cache manager test dir $cp exists.");

mkdir("$cp/$DATA_DN");
ok(-d "$cp/$DATA_DN", "cache manager DATA_DN $cp/$DATA_DN exists.");

make_file("$cp/$GLOBAL_LOCK_FN", "no\n");
make_file("$ccidfn", "2\n");
make_file("$lcidfn", "2\n");

mkdir("$cp/profile.1");
mkdir("$cp/profile.2");
ok(-d "$cp/profile.1", "cache manager profile.1 dir exists.");
ok(-d "$cp/profile.2", "cache manager profile.1 dir exists.");

my $cfgl;
my $cfgu;

my $cm;
ok ($cm = EDG::WP4::CCM::CacheManager->new($cp), 
    "EDG::WP4::CCM::CacheManager->new($cp)");

ok (EDG::WP4::CCM::Configuration::_touch_file("$cp/tf"), 
    "EDG::WP4::CCM::Configuration::_touch_file($cp/tf)");
unlink ("$cp/tf");


my $self = {
    "cid" => 1,
    "locked" => 1,
    "cache_path" => $cp,
    "cfg_path" => "$cp/profile.1",
    "cache_manager" => $cm
    };

my $tpf1 = "$cp/profile.1/ccm-active-profile.1-".getpid();
ok (EDG::WP4::CCM::Configuration::_create_pid_file($self),
    "EDG::WP4::CCM::Configuration::_create_pid_file($self)");
ok (-f $tpf1, "-f $tpf1");
bless ($self, "EDG::WP4::CCM::Configuration");
my $tpf2 = "$cp/profile.2/ccm-active-profile.2-".getpid();
ok (EDG::WP4::CCM::Configuration::_update_cid_pidf($self) &&
    ($self->{"cid"} == 2) && -f $tpf2,
    "EDG::WP4::CCM::Configuration::_update_cid_pidf($self)");
$self=();
ok (($cfgl = EDG::WP4::CCM::Configuration->new ($cm, 1, 1)) &&
    -f "$cp/profile.1/ccm-active-profile.1-".getpid(),
    "EDG::WP4::CCM::Configuration->new ($cm, 1, 1)");
ok (($cfgu = EDG::WP4::CCM::Configuration->new ($cm, 2, 0)) &&
    -f "$cp/profile.2/ccm-active-profile.2-".getpid(),
    "EDG::WP4::CCM::Configuration->new ($cm, 2, 0)");

is ($cfgl->isLocked(), 1, "$cfgl->isLocked()");
is ($cfgu->isLocked(), 0, "$cfgu->isLocked()");

is ($cfgl->getConfigurationId(), 1, "$cfgl->getConfigurationId()==1");
is ($cfgu->getConfigurationId(), 2, "$cfgl->getConfigurationId()==2");

#TODO: test behaviour of the locked and unlocked configuration
#TODO: when getElement function is used

ok ($cfgl->unlock() && !$cfgl->isLocked() &&
    !-f "$cp/profile.1/active.".getpid(), "$cfgl->unlock()");
ok ($cfgu->lock() && $cfgu->isLocked() &&
    -f "$cp/profile.2/ccm-active-profile.2-".getpid(), "$cfgu->lock");

is ($cfgl->getConfigurationId(), 2, "$cfgl->getConfigurationId()==2");
is ($cfgu->getConfigurationId(), 2, "$cfgl->getConfigurationId()==2");

ok ($cfgu->unlock() && !$cfgu->isLocked(), "$cfgu->unlock()");
ok ($cfgl->lock() && $cfgl->isLocked(), "$cfgl->lock");

is ($cfgl->getConfigurationId(), 2, "$cfgl->getConfigurationId()==2");
is ($cfgu->getConfigurationId(), 2, "$cfgl->getConfigurationId()==2");

$cfgl = ();
ok (-f "$cp/profile.2/ccm-active-profile.2-".getpid(), 
    "cfg1 = undef && -f $cp/profile.2/ccm-active-profile.2-".getpid());
$cfgu = ();
ok (!-f "$cp/profile.2/active.".getpid(), 
    "cfg2 = undef && !-f $cp/profile.2/active.".getpid());

done_testing();
