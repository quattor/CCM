use strict;
use warnings;

use Test::More;

use EDG::WP4::CCM::CCfg;

BEGIN {
    # Force typed json for improved testing
    # Use BEGIN to make sure it is executed before the import from Test::Quattor
    ok(EDG::WP4::CCM::CCfg::_setCfgValue('json_typed', 1), 'json_typed enabled');
}

use Test::Quattor qw(format);
use EDG::WP4::CCM::Format;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

my $cfg = get_config_for_profile("format");
my ($el, $fmt);


$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('json', $el);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
is("$fmt",
   '{"a":1,"b":1.5,"c":{"f":false,"t":true},"d":"test"}'."\n",
   "JSON format");

$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('yaml', $el);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
my $txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   "---a:1b:1.5c:f:falset:trued:test",
   "YAML format");

done_testing();
