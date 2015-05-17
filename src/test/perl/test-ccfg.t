#
# CCfg test
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw (@CONFIG_OPTIONS $CONFIG_FN);
use Cwd;
use Net::Domain qw(hostname hostdomain);
use Readonly;

my $host   = hostname();
my $domain = hostdomain();

ok($host,   "Net::Domain::hostname");
ok($domain, "Net::Domain::hostdomain()");

my $ccfgtmp = getcwd() . "/src/test/resources/";

my $ccfgconfig = getcwd() . "/src/main/conf/ccm.conf";

my $ec = LC::Exception::Context->new->will_store_errors;

# test the resolveTags  method
is(EDG::WP4::CCM::CCfg::_resolveTags("a"),       "a",     "_resolveTags(a)");
is(EDG::WP4::CCM::CCfg::_resolveTags('$host'),   $host,   '_resolveTags($host)');
is(EDG::WP4::CCM::CCfg::_resolveTags('$domain'), $domain, '_resolveTags($domain)');
is(EDG::WP4::CCM::CCfg::_resolveTags('$host$domain'), $host . $domain,
    '_resolveTags($host$domain)');
is(
    EDG::WP4::CCM::CCfg::_resolveTags('$hosthost$domaindomain'),
    $host . "host" . $domain . "domain",
    '_resolveTags($hosthost$domaindomain)'
);
is(EDG::WP4::CCM::CCfg::_resolveTags('$host$domain$host$domain'),
    "$host$domain$host$domain", '_resolveTags($host$domain$host$domain)');
is(
    EDG::WP4::CCM::CCfg::_resolveTags(':$host/$domain/$host/$domain'),
    ":$host/$domain/$host/$domain",
    '_resolveTags(:$host/$domain/$host/$domain)'
);


# unittest to check empty/non-existing/invalid keyword

my $fn = "$ccfgtmp/notexists";
my $fh = CAF::FileReader->new($fn);
ok(!-f $fn, "notexists file $fn doesn't exist");

eok($ec, EDG::WP4::CCM::CCfg::initCfg($fn), "initCfg of not existing file");

$fn = "$ccfgtmp/ccm_invalidkey.cfg";
ok(-f $fn, "ccm_invalidkey file $fn does exist");
eok($ec, EDG::WP4::CCM::CCfg::_readConfigFile($fn), "_readConfigFile with invalid key");

$fn = "$ccfgtmp/ccm.cfg";
ok(-f $fn,                            "ccm cfg file $fn does exist");
ok(EDG::WP4::CCM::CCfg::initCfg($fn), "initialise CCfg");

my %expected = (

    # from the file
    debug            => 0,
    get_timeout      => 1,
    profile          => 'https://www.google.com',
    cache_root       => 'target/test/cache',
    retrieve_wait    => 0,
    retrieve_retries => 1,

    # from the defaults
    keep_old   => 2,
    purge_time => 86400,
);
while (my ($k, $v) = each %expected) {
    is(EDG::WP4::CCM::CCfg::getCfgValue($k), $v, "Get ccfg param $k");
}

# test the config we ship
ok(-f $ccfgconfig,                            "ccm cfg file $ccfgconfig does exist");
ok(EDG::WP4::CCM::CCfg::initCfg($ccfgconfig), "initialise CCfg");

%expected = (

    # from the file
    profile          => 'http://host.mydomain.org/profiles/'.EDG::WP4::CCM::CCfg::_resolveTags('$host').'.xml',
    debug            => 0,
    force            => 0,
    cache_root       => '/var/lib/ccm',
    get_timeout      => 30,
    lock_retries     => 3,
    lock_wait        => 30,
    retrieve_retries => 3,
    retrieve_wait    => 30,
    world_readable   => 0,
);
while (my ($k, $v) = each %expected) {
    is(EDG::WP4::CCM::CCfg::getCfgValue($k), $v, "Get ccm.conf ccfg param $k");
}

# Hard test for possible values
# (based on original 15.4 code)
Readonly::Hash my %DEFAULT_CFG => {
    "base_url" => undef,
    "ca_dir" => undef,
    "ca_file" => undef,
    "cache_root" => "/var/lib/ccm",
    "cert_file" => undef,
    "context" => undef,
    "dbformat" => "GDBM_File",
    "debug" => undef,
    "force" => undef,
    "get_timeout" => 30,
    "json_typed" => 0,
    "keep_old" => 2,
    "key_file" => undef,
    "lock_retries" => 3,
    "lock_wait" => 30,
    "preprocessor" => undef,
    "profile" => undef,
    "profile_failover" => undef,
    "purge_time" => 86400,
    "retrieve_retries" => 3,
    "retrieve_wait" => 30,
    "trust" => undef,
    "world_readable" => undef,
};
my %default_cfg = map {$_->{option} => $_->{DEFAULT}} @CONFIG_OPTIONS;
is_deeply(\%DEFAULT_CFG, \%default_cfg,
          "Expected default configuration options");

# Exported default config file
is($CONFIG_FN, "/etc/ccm.conf", "Expected default ccm config file");

done_testing();
