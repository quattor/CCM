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
use Test::Quattor::Object;
use Test::Quattor::TextRender::Base;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

my $cfg = get_config_for_profile("format");
my ($el, $fmt);

my $caf_trd = mock();
my $log = Test::Quattor::Object->new();

=pod

=head2 json

=cut

$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('json', $el, log => $log);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
is("$fmt",
   '{"a":1,"b":1.5,"c":{"f":false,"t":true},"d":"test"}'."\n",
   "JSON format");
ok(! $log->{LOGCOUNT}->{ERROR}, "No errors logged for JSON format");

=pod

=head2 yaml

=cut

$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('yaml', $el, log => $log);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
my $txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   "---a:1b:1.5c:f:falset:trued:test",
   "YAML format");
ok(! $log->{LOGCOUNT}->{ERROR}, "No errors logged for YAML format");


=pod

=head2 pan

Test pan format (more tests in TT testsuite)

=cut

$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('pan', $el, log => $log);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
$txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   '"/a"=1;#long"/b"=1.5;#double"/c/f"=false;#boolean"/c/t"=true;#boolean"/d"="test";#string',
   "pan format");

ok(! $log->{LOGCOUNT}->{ERROR}, "No errors logged for pan format");

=pod

=head2 pancxml

Test pancxml format (more tests in TT testsuite)

=cut

$el = $cfg->getElement("/");
$fmt = EDG::WP4::CCM::Format->new('pancxml', $el, log => $log);
isa_ok($fmt, 'EDG::WP4::CCM::Format', "a EDG::WP4::CCM::Format instance");
$txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   '<?xmlversion="1.0"encoding="UTF-8"?><nlistformat="pan"name="profile"><longname="a">1</long><doublename="b">1.5</double><nlistname="c"><booleanname="f">false</boolean><booleanname="t">true</boolean></nlist><stringname="d">test</string></nlist>',
   "pancxml format");

ok(! $log->{LOGCOUNT}->{ERROR}, "No errors logged for pan format");

done_testing();
