use strict;
use warnings;

use Test::More;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use EDG::WP4::CCM::App::Options;
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN);
use Test::MockModule;

my $apppath = "target/sbin/ccm";
my $opts = EDG::WP4::CCM::App::Options->new(
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    );

isa_ok($opts, "EDG::WP4::CCM::App::Options",
       "EDG::WP4::CCM::App::Options instance created");

my $options = $opts->app_options();
my %optshash = map { $_->{NAME} => $_->{DEFAULT} } @$options;

my $custom = {
    'cfgfile=s' => $CONFIG_FN,
};
foreach my $opt (@CONFIG_OPTIONS) {
    $custom->{$opt->{option}.($opt->{suffix} || '')} = $opt->{DEFAULT};
}

is_deeply(\%optshash, $custom, "Found expected options and defaults");

# verify values read from ccm.cfg

my $ccmcfgopts = {
    debug => 0,
    get_timeout => 1,
    profile => 'https://www.google.com',
    cache_root => 'target/test/cache',
    retrieve_wait => 0,
    retrieve_retries => 1,
};

foreach my $k (sort keys %$ccmcfgopts) {
    my $v = $ccmcfgopts->{$k};
    is($opts->option($k), $v, "$k value $v in ccm.cfg");
};

# Actually test a CCM app instance using existing CCM
# Cannot use Test::Quattor import due to CAF mocking
my $ppc_cfg = prepare_profile_cache('app_options');

my $newopts = EDG::WP4::CCM::App::Options->new(
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    '--cache_root', $ppc_cfg->{cache_path},
    );
isa_ok($newopts, "EDG::WP4::CCM::App::Options",
       "EDG::WP4::CCM::App::Options instance created");
ok($newopts->setCCMConfig(), "Created the CCM config (no cid)");

isa_ok($newopts->{CACHEMGR}, "EDG::WP4::CCM::CacheManager",
       "CACHEMGR attribute returns EDG::WP4::CCM::CacheManager instance");
isa_ok($newopts->{CCM_CONFIG}, "EDG::WP4::CCM::Configuration",
       "CCM_CONFIG attribute returns EDG::WP4::CCM::Configuration instance");

my $cfg = $newopts->getCCMConfig();
isa_ok($cfg, "EDG::WP4::CCM::Configuration",
       "getCCMConfig returns EDG::WP4::CCM::Configuration instance");
is($cfg, $newopts->{CCM_CONFIG}, "getCCMConfig returns expected instance");

# Check data
is_deeply($cfg->getTree("/"), {a => 'b'}, "Read CCM returns correct data");

done_testing();
