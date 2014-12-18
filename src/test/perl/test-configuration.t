#
# cache Configuration.pm test script
#

use strict;
use warnings;

use POSIX qw (getpid);
use Test::More;
use CCMTest qw (eok make_file);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN 
				      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use Cwd;

my $ec = LC::Exception::Context->new->will_store_errors;

my $cptmp = getcwd()."/target/tmp";
my $cp = "$cptmp/configuration-test";

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
ok(-d "$cp/profile.2", "cache manager profile.2 dir exists.");

my ($cfgl, $cfgl_pfn, $cfgl_pfn_new, $cfgu, $cfgu_pfn, $cm);

ok ($cm = EDG::WP4::CCM::CacheManager->new($cp), 
    "EDG::WP4::CCM::CacheManager->new($cp)");

is($cm->getCurrentCid(), '2', 'cache_manager cid is 2');

ok (EDG::WP4::CCM::Configuration::_touch_file("$cp/tf") && -f "$cp/tf", 
    "EDG::WP4::CCM::Configuration::_touch_file($cp/tf)");
unlink ("$cp/tf");


my $self = {
    "cid" => 1,
    "locked" => 1,
    "cache_path" => $cp,
    "cfg_path" => "$cp/profile.1",
    "cache_manager" => $cm,
    "anonymous" => 1,
    };

bless ($self, "EDG::WP4::CCM::Configuration");

# Start with anonymous test
my $tpf1 = "$cp/profile.1/ccm-active-profile.1-".getpid();
ok (EDG::WP4::CCM::Configuration::_create_pid_file($self),
    "EDG::WP4::CCM::Configuration::_create_pid_file($self)");
ok (! -f $tpf1, "! -f tpf1 $tpf1 with anonymous");
is($tpf1, $self->_pid_filename(), "Correct pid filename for tpf1 (_create_pid_file)");
is ($self->{cid_to_number}{$self->{cid}}, 1 , "1 configuration instances active (i.e. tpf1)");

# Test without anonymous / default behaviour
$self->{anonymous} = undef;
$self->{cid_to_number}{$self->{cid}} = undef;

ok (EDG::WP4::CCM::Configuration::_create_pid_file($self),
    "EDG::WP4::CCM::Configuration::_create_pid_file($self)");
ok (-f $tpf1, "-f tpf1 $tpf1 without anonymous");
is($tpf1, $self->_pid_filename(), "Correct pid filename for tpf1 (_create_pid_file)");
is ($self->{cid_to_number}{$self->{cid}}, 1 , "1 configuration instances active (i.e. tpf1)");

# update to the cache_manager current cid (which is 2)
my $oldcid=$self->{cid};
my $tpf2 = "$cp/profile.2/ccm-active-profile.2-".getpid();
ok (EDG::WP4::CCM::Configuration::_update_cid_pidf($self) &&
    ($self->{"cid"} == 2),
    "EDG::WP4::CCM::Configuration::_update_cid_pidf($self)");
ok (-f $tpf2, "-f tpf2 $tpf2");
is($tpf2, $self->_pid_filename(), "Correct pid filename for tpf2 (after _update_cid_pidf)");
ok (! -f $tpf1, "tpf1 $tpf1 does not exist anymore (after _update_cid_pidf)");
is ($self->{cid_to_number}{$self->{cid}}, 1 , "1 configuration instances active (i.e. tpf1)");
is ($self->{cid_to_number}{$oldcid}, 0 , "0 configuration instances active with oldcid");

$self=();
ok(! -f $tpf2, "Removed tpf2 $tpf2 after destroy");

#
# Regular usage via ->new()
#
$cfgl = EDG::WP4::CCM::Configuration->new ($cm, 1, 1);
isa_ok($cfgl, "EDG::WP4::CCM::Configuration", "cfgl is a EDG::WP4::CCM::Configuration");
$cfgl_pfn = $cfgl->_pid_filename();
is($cfgl_pfn, "$cp/profile.1/ccm-active-profile.1-".getpid(), "cfgl has correct pid filename");
ok (-f $cfgl_pfn, "cfgl pid filename found");

$cfgu = EDG::WP4::CCM::Configuration->new ($cm, 2, 0);
isa_ok($cfgu, "EDG::WP4::CCM::Configuration", "cfgu is a EDG::WP4::CCM::Configuration");
$cfgu_pfn = $cfgu->_pid_filename();
is($cfgu_pfn, "$cp/profile.2/ccm-active-profile.2-".getpid(), "cfgu has correct pid filename");
ok (-f $cfgu_pfn, "cfgu pid filename found");

is ($cfgl->{cid_to_number}{$cfgl->{cid}}, 1 , "1 configuration instances active (i.e. cfgl)");
is ($cfgu->{cid_to_number}{$cfgu->{cid}}, 1 , "1 configuration instances active (i.e. cfgu)");


is ($cfgl->isLocked(), 1, '$cfgl->isLocked() gives 1');
is ($cfgu->isLocked(), 0, '$cfgu->isLocked() gives 0');

# Nothing changed so far
is ($cfgl->{cache_manager}->getCurrentCid(), 2, 
    '$cfgl->{cache_manager}->getCurrentCid()==2');
is ($cfgu->{cache_manager}->getCurrentCid(), 2, 
    '$cfgl->{cache_manager}->getCurrentCid()==2');

# triggers a _update_cid_pidf for unlocked
is ($cfgl->getConfigurationId(), 1, '$cfgl->getConfigurationId()==1');
ok (-f $cfgl_pfn, "cfgl pid filename still present after getConfigurationId");

is ($cfgu->getConfigurationId(), 2, '$cfgu->getConfigurationId()==2');


#TODO: test behaviour of the locked and unlocked configuration
#TODO: when getElement function is used

ok (-f $cfgl_pfn, "cfgl pid filename exists before unlock");
is ($cfgl->{cid_to_number}{$cfgl->{cid}}, 1 , "1 configuration instances active (i.e. cfgl)");
# triggers a _update_cid_pidf
ok ($cfgl->unlock() , '$cfgl->unlock()');
ok(!$cfgl->isLocked(), '$cfgl unlocked');
$cfgl_pfn_new = $cfgl->_pid_filename();
ok($cfgl_pfn_new ne $cfgl_pfn, "cfgl has new pid filename after unlock");
ok(! -f $cfgl_pfn, "old cfgl pid filename does not exist anymore");
ok(-f $cfgl_pfn_new, "(new) cfgl pid filename found");
is($cfgl_pfn_new, $cfgu_pfn, "new cfgl pid filename same as cfgu");

is ($cfgl->{cid}, 2, "cfgl cid updated"); 
is ($cfgl->{cid_to_number}{$cfgl->{cid}}, 1, 
    "1 configuration instance active (i.e. cfgl)");
is ($cfgl->{cid_to_number}{1}, 0, 
    "0 configuration instances active on same old cfgl profile/pid/cid as cfgl, counter decreased");


ok (-f $cfgu_pfn, "cfgu pid filename found before unlock");
ok ($cfgu->lock() && $cfgu->isLocked(), '$cfgu->lock');
ok (-f $cfgu_pfn, "cfgu pid filename still found after unlock");

is ($cfgl->getConfigurationId(), 2, '$cfgl->getConfigurationId()==2');
is ($cfgl->{cid_to_number}{$cfgl->{cid}}, 1, 
    "2 configuration instances active on same profile/pid/cid as cfgl, counter not updated ");

is ($cfgu->{cid_to_number}{$cfgu->{cid}}, 1 ,
    "2 configuration instances active on same profile/pid/cid as cfgu, counter not updated");

is ($cfgu->getConfigurationId(), 2, '$cfgl->getConfigurationId()==2');

ok (-f $cfgu_pfn, "cfgu pid filename found before re-unlock");
ok ($cfgu->unlock() && !$cfgu->isLocked(), 'cfgu->unlock()');
ok (-f $cfgu_pfn, "cfgu pid filename found after re-unlock (already correct cache_manager current cid)");

ok (-f $cfgl_pfn_new, "cfgl pid filename exists before re-lock");
ok ($cfgl->lock() && $cfgl->isLocked(), '$cfgl->lock');
ok (-f $cfgl_pfn_new, "cfgl pid filename still exists after re-lock (already updated before)");

is ($cfgl->getConfigurationId(), 2, '$cfgl->getConfigurationId()==2');
is ($cfgu->getConfigurationId(), 2, '$cfgl->getConfigurationId()==2');


# =() triggers DESTROY
ok (-f $cfgl_pfn_new, "before cfg1 = undef && -f $cfgl_pfn_new");
$cfgl = ();

TODO: {
    local $TODO = "The test-configuration.pl also fails in 14.10 release in this step.";
    # 14.10 fail output:
    # not ok 20 - cfg1 = undef && -f /tmp/c-test/profile.2/ccm-active-profile.2-10625
    #   Failed test 'cfg1 = undef && -f /tmp/c-test/profile.2/ccm-active-profile.2-10625'
    #   at ./test-configuration.pl line 101.
    
    # why would the file still exists? nothing protects it against removal?
    # cfgl can't see the counters of cfgu.
    
    ok (-f $cfgl_pfn_new, "cfg1 = undef && -f $cfgl_pfn_new");

    ok (-f $cfgu_pfn, "before cfg2 = undef && !-f $cfgu_pfn");
};

$cfgu = ();
ok (!-f $cfgu_pfn, "cfg2 = undef && !-f $cfgu_pfn");

done_testing();
