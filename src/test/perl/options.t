use strict;
use warnings;

use Test::More;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use EDG::WP4::CCM::Options;
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN);
use EDG::WP4::CCM::Element qw(escape);
use Test::MockModule;

my $optmock = Test::MockModule->new('EDG::WP4::CCM::Options');

my $apppath = "target/sbin/ccm";
my $opts = EDG::WP4::CCM::Options->new(
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    );

isa_ok($opts, "EDG::WP4::CCM::Options",
       "EDG::WP4::CCM::Options instance created");

my $options = $opts->app_options();
my %optshash = map { $_->{NAME} => $_->{DEFAULT} } @$options;

my $custom = {
    'cfgfile=s' => $CONFIG_FN,
    'cid=s' => undef,
    'showcids' => undef,
    'profpath=s@' => undef,
    'component=s@' => undef,
    'metaconfig=s@' => undef,
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
my $ppc_cfg = prepare_profile_cache('options');

# --cid is not really tested as latest, current and most recent are all the same profile
my $newopts = EDG::WP4::CCM::Options->new(
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    '--cache_root', $ppc_cfg->{cache_path},
    '--cid', "latest", # use latest CID as defined in the latest.cid file
    '--profpath', '/a/b/c', '--profpath', '/d/e/f',
    '--metaconfig', '/etc/special', '--metaconfig', '/etc/veryspecial',
    '--component', 'mycomponent', '--component', 'othercomponent',
    );
isa_ok($newopts, "EDG::WP4::CCM::Options",
       "EDG::WP4::CCM::Options instance created");
ok($newopts->setCCMConfig(), "Created the CCM config (no cid passed)");

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

# gatherPaths: option name sorted
is_deeply($newopts->gatherPaths('/initialpath/1', '/initialpath/2'),
          ['/initialpath/1',
           '/initialpath/2',
           '/software/components/mycomponent', # component
           '/software/components/othercomponent',
           '/software/components/metaconfig/services/'. escape('/etc/special') ."/contents", # metaconfig
           '/software/components/metaconfig/services/'. escape('/etc/veryspecial') . "/contents",
           '/a/b/c', # profpath
           '/d/e/f',
          ],
          "Expected gatherPaths");

# Default action
ok(! $newopts->default_action(), "No default action by default");
ok(! $newopts->default_action('notanaction'), "Default action not modifed for unsupported action");
ok(! $newopts->default_action(), "Still no default action");

# a valid action (is check a bit later by itself)
my @expected = qw(showcids);

is($newopts->default_action($expected[0]), $expected[0],
   "Set default action and returns the default value");
is($newopts->default_action(), $expected[0],
   "Expected default action");
ok(! $newopts->default_action(''), "Unset default action");
ok(! $newopts->default_action(), "Default action unset");

# default action is called when no action is set
my $called = 0;
# return undef, as if nothing was configured
$optmock->mock('default_action', sub {$called++; return});
ok($newopts->action(),
   'action returns success even when no actions (or default action) is defined');
is($called, 1, 'Default action called when no action defined');

# Test add_actions
my $actions = $newopts->add_actions();
is_deeply([sort keys %$actions], \@expected,
          "Expected default actions");

$actions = $newopts->add_actions({
    zzz_newact => "new action",
});
is_deeply([sort keys %$actions], \@expected,
          "Expected actions (action not added if method doesn't exist)");

# "create" the action
$optmock->mock('action_zzz_newact', 1);
$actions = $newopts->add_actions({
    zzz_newact => "new action",
});
push(@expected, "zzz_newact");
is_deeply([sort keys %$actions], \@expected,
          "Expected actions after adding newact with existing acion_ method");

# showcids action
my @print;
$optmock->mock('_print', sub {shift; @print = @_;});

my $showcids = EDG::WP4::CCM::Options->new(
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    '--cache_root', $ppc_cfg->{cache_path},
    '--showcids',
    );
isa_ok($showcids, "EDG::WP4::CCM::Options",
       "EDG::WP4::CCM::Options instance created");

# hmm, there's only one (so no comma-join is tested)
ok($showcids->action(), "action with showcids returns success");
is_deeply(\@print, [2, "\n"], "showcids gives correct result");

$optmock->unmock('_print');

done_testing();
