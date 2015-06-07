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
use EDG::WP4::CCM::TextRender qw(ccm_format @CCM_FORMATS);
use Test::Quattor::Object;
use Test::Quattor::TextRender::Base;
use XML::Parser;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

is_deeply(\@CCM_FORMATS, 
          [qw(json pan pancxml yaml)],
          "Expected supported CCM formats"
    );

my $cfg = get_config_for_profile("format");
my ($el, $fmt);

my $caf_trd = mock();
my $log = Test::Quattor::Object->new();

=pod

unsupported format

=cut

$el = $cfg->getElement("/");
ok(! defined(ccm_format('notasupportedformat', $el)), 
   "ccm_format returns undef for unsupported format");

=pod

=head2 json

=cut

$el = $cfg->getElement("/");
$fmt = ccm_format('json', $el);
isa_ok($fmt, 'EDG::WP4::CCM::TextRender', "a EDG::WP4::CCM::TextRender instance");
is("$fmt",
   '{"a":1,"b":1.5,"c":{"f":false,"t":true},"d":"test"}'."\n",
   "JSON format");

=pod

=head2 yaml

=cut

$el = $cfg->getElement("/");
$fmt = ccm_format('yaml', $el);
isa_ok($fmt, 'EDG::WP4::CCM::TextRender', "a EDG::WP4::CCM::TextRender instance");
my $txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   "---a:1b:1.5c:f:falset:trued:test",
   "YAML format");

=pod

=head2 pan

Test pan format (more tests in TT testsuite)

=cut

$el = $cfg->getElement("/");
$fmt = ccm_format('pan', $el);
isa_ok($fmt, 'EDG::WP4::CCM::TextRender', "a EDG::WP4::CCM::TextRender instance");
$txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   '"/a"=1;#long"/b"=1.5;#double"/c/f"=false;#boolean"/c/t"=true;#boolean"/d"="test";#string',
   "pan format");

=pod

=head2 pancxml

Test pancxml format (more tests in TT testsuite)

=cut

$el = $cfg->getElement("/");
$fmt = ccm_format('pancxml', $el);
isa_ok($fmt, 'EDG::WP4::CCM::TextRender', "a EDG::WP4::CCM::TextRender instance");

my $p = XML::Parser->new(Style => 'Tree');
my $t;
eval { $t = $p->parse("$fmt"); };
ok(! @$, "No XML parsing errors");

$txt = "$fmt";
$txt =~ s/\s//g; # squash all whitespace
is($txt,
   '<?xmlversion="1.0"encoding="UTF-8"?><nlistformat="pan"name="profile"><longname="a">1</long><doublename="b">1.5</double><nlistname="c"><booleanname="f">false</boolean><booleanname="t">true</boolean></nlist><stringname="d">test</string></nlist>',
   "pancxml format");

done_testing();
