#
# CCfg test
#

use strict;
use warnings;

use Test::More;
use CCMTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw (@CONFIG_OPTIONS $CONFIG_FN @CFG_KEYS
    initCfg getCfgValue setCfgValue resetCfg);
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
is(EDG::WP4::CCM::CCfg::_resolveTags("a"), "a",
   "_resolveTags(a) returned (unexpanded) a");

is(EDG::WP4::CCM::CCfg::_resolveTags('__HOST__'), $host,
   '_resolveTags(__HOST__) correctly expanded __HOST__');
is(EDG::WP4::CCM::CCfg::_resolveTags('__DOMAIN__'), $domain,
   '_resolveTags(__DOMAIN__) correctly expanded __DOMAIN__');
is(EDG::WP4::CCM::CCfg::_resolveTags('__HOST____DOMAIN__'), $host . $domain,
    '_resolveTags(__HOST____DOMAIN__) correctly expanded __HOST__ followed by __DOMAIN__');
is(EDG::WP4::CCM::CCfg::_resolveTags('__HOST__host__DOMAIN__domain'),
   $host . "host" . $domain . "domain",
   '_resolveTags(__HOST__host__DOMAIN__domain) correctly expanded __HOST__ followed by __DOMAIN__ with some letters in between');
is(EDG::WP4::CCM::CCfg::_resolveTags('__HOST____DOMAIN____HOST____DOMAIN__'),
    "$host$domain$host$domain",
   '_resolveTags(__HOST____DOMAIN____HOST____DOMAIN__) correctly expanded __HOST__ followed by __DOMAIN__ followed by __HOST__ followed by __DOMAIN__');

is(EDG::WP4::CCM::CCfg::_resolveTags(':__HOST__/__DOMAIN__/__HOST__/__DOMAIN__'),
   ":$host/$domain/$host/$domain",
   '_resolveTags(:__HOST__/__DOMAIN__/__HOST__/__DOMAIN__) correctly expanded __HOST__ followed by __DOMAIN__ followed by __HOST__ followed by __DOMAIN__ separated by /');

# deprecated $host / $domain
is(EDG::WP4::CCM::CCfg::_resolveTags('$host'), $host,
   '_resolveTags($host) correctly expanded $host');
is(EDG::WP4::CCM::CCfg::_resolveTags('$domain'), $domain,
   '_resolveTags($domain) correctly expanded $domain');
is(EDG::WP4::CCM::CCfg::_resolveTags('$host$domain'), $host . $domain,
    '_resolveTags($host$domain) correctly expanded $host forllowed by $domain');
is(EDG::WP4::CCM::CCfg::_resolveTags('$hosthost$domaindomain'),
   $host . "host" . $domain . "domain",
   '_resolveTags($hosthost$domaindomain) correctly expanded $host followed by $domain with some letters in between');
is(EDG::WP4::CCM::CCfg::_resolveTags('$host$domain$host$domain'),
    "$host$domain$host$domain", '_resolveTags($host$domain$host$domain) correctly expanded $host followed by $domain followed by $host followed by $domain');
is(EDG::WP4::CCM::CCfg::_resolveTags(':$host/$domain/$host/$domain'),
   ":$host/$domain/$host/$domain",
   '_resolveTags(:$host/$domain/$host/$domain) correctly expanded $host followed by $domain followed by $host followed by $domain separated by /');


# unittest to check empty/non-existing/invalid keyword

my $fn = "$ccfgtmp/notexists";
my $fh = CAF::FileReader->new($fn);
ok(!-f $fn, "notexists file $fn doesn't exist");

eok($ec, initCfg($fn), "initCfg of not existing file");

$fn = "$ccfgtmp/ccm_invalidkey.cfg";
ok(-f $fn, "ccm_invalidkey file $fn does exist");
eok($ec, EDG::WP4::CCM::CCfg::_readConfigFile($fn), "_readConfigFile with invalid key");

$fn = "$ccfgtmp/ccm.cfg";
ok(-f $fn,                            "ccm cfg file $fn does exist");
ok(initCfg($fn), "initialise CCfg");

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
    is(getCfgValue($k), $v, "Get ccfg param $k");
}

# Test setCfgValue
while (my ($k, $v) = each %expected) {
    my $newvalue = "new$v";
    is(setCfgValue($k, $newvalue), $newvalue, "Set ccfg param $k to $newvalue");
    is(getCfgValue($k), $newvalue, "Get new ccfg param $k");
}

# Re-init
ok(initCfg($fn), "re initialise CCfg pt1");
while (my ($k, $v) = each %expected) {
    if ($k =~ m/^(keep_old|purge_time)$/) {
        # not via configfile
        $v = "new$v";
    }
    is(getCfgValue($k), $v, "Get ccfg param $k after reinit pt1");
}

# Force them
while (my ($k, $v) = each %expected) {
    my $newvalue = "new$v";
    is(setCfgValue($k, $newvalue, 1), $newvalue, "Set ccfg param $k to $newvalue after reinit pt1 with force");
    is(getCfgValue($k), $newvalue, "Get new ccfg param $k after reinit pt1 with force");
}

# Re-init with forced
ok(initCfg($fn), "re initialise CCfg pt2");
while (my ($k, $v) = each %expected) {
    my $newvalue = "new$v";
    is(getCfgValue($k), $newvalue, "Get ccfg param $k after reinit pt2 with forced values");
}

# Reset everything and reread. Forced should be cleared.
resetCfg();
ok(initCfg($fn), "re initialise CCfg pt3");
while (my ($k, $v) = each %expected) {
    is(getCfgValue($k), $v, "Get ccfg param $k after reinit pt3 and reset");
}


# test the config we ship
ok(-f $ccfgconfig,                            "ccm cfg file $ccfgconfig does exist");
ok(initCfg($ccfgconfig), "initialise CCfg");

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
    is(getCfgValue($k), $v, "Get ccm.conf ccfg param $k");
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
    "group_readable" => undef,
    "json_typed" => 1,
    "keep_old" => 2,
    "key_file" => undef,
    "keytab" => undef,
    "lock_retries" => 3,
    "lock_wait" => 30,
    "preprocessor" => undef,
    "principal" => undef,
    "profile" => undef,
    "profile_failover" => undef,
    "purge_time" => 86400,
    "retrieve_retries" => 3,
    "retrieve_wait" => 30,
    "tabcompletion" => 1,
    "trust" => undef,
    "world_readable" => undef,
};
my %default_cfg = map {$_->{option} => $_->{DEFAULT}} @CONFIG_OPTIONS;
is_deeply(\%DEFAULT_CFG, \%default_cfg,
          "Expected default configuration options");

# All CONFIG_OPTIONS hasve nonempty HELP
foreach my $opt (@CONFIG_OPTIONS) {
    ok($opt->{HELP}, "Non-empty HELP for CONFIG_OPTIONS $opt->{option}");
}

# Exported default config file
is($CONFIG_FN, "/etc/ccm.conf", "Expected default ccm config file");

# Hard test for possible values (sorted)
is_deeply(\@CFG_KEYS, [qw(base_url ca_dir ca_file cache_root cert_file
context dbformat debug force get_timeout group_readable json_typed keep_old
key_file keytab lock_retries lock_wait preprocessor principal profile profile_failover
purge_time retrieve_retries retrieve_wait tabcompletion trust world_readable
)], "CFG_KEYS exports all possible configuration keys");


done_testing();
