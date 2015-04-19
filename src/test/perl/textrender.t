use strict;
use warnings;

use Test::More;

use EDG::WP4::CCM::CCfg;

BEGIN {
    # Force typed json for improved testing
    # Use BEGIN to make sure it is executed before the import from Test::Quattor
    ok(EDG::WP4::CCM::CCfg::_setCfgValue('json_typed', 1), 'json_typed enabled');
}

use Readonly;
use Test::Quattor qw(textrender);
use EDG::WP4::CCM::TextRender;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

=pod

=head2 Test contents failure

=cut

my $brokencont = EDG::WP4::CCM::TextRender->new('yaml', [qw(not_a_hash_nor_Element)]);
isa_ok ($brokencont, "EDG::WP4::CCM::TextRender", "Correct class after new method (but with broken contents)");
ok(! defined($brokencont->get_text()), "get_text returns undef, contents failed");
is("$brokencont", "", "render failed, stringification returns empty string");
like($brokencont->{fail},
     qr{Contents passed is neither a hashref or a EDG::WP4::CCM::Element instance \(ref ARRAY\)},
     "Error is reported");

# not cached
ok(!exists($brokencont->{_cache}), "Render failed, no caching of the event. (Failure will be recreated)");


=pod

=head2 contents is element

Test the contents is element, and getTree element options

=cut

my $cfg = get_config_for_profile("textrender");
my ($el, $trd);

# json module

$el = $cfg->getElement("/");
$trd = EDG::WP4::CCM::TextRender->new('json', $el);
is("$trd",
   '{"a":"a","b":"1","c":1,"d":true,"e":false,"f":1.5,"g":["g1","g2"],"h":{"a":"a","b":"1","c":1,"d":true,"e":false}}'."\n",
   "Correct JSON rendered");

# not quoted / true
my $fakeyamlbool = ' '.$EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{yaml_boolean}->(1)."\nx";
is($trd->_yaml_replace_boolean_prefix($fakeyamlbool),
   " true\nx",
   'Search and replace YAML boolean true');
# double quoted / true
$fakeyamlbool = ' "'.$EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{yaml_boolean}->(1)."\"\nx";
is($trd->_yaml_replace_boolean_prefix($fakeyamlbool),
   " true\nx",
   'Search and replace YAML boolean true');
# single quoted / false
$fakeyamlbool = " '".$EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{yaml_boolean}->(0)."'\nx";
is($trd->_yaml_replace_boolean_prefix($fakeyamlbool),
   " false\nx",
   'Search and replace YAML boolean true');

$el = $cfg->getElement("/");
$trd = EDG::WP4::CCM::TextRender->new('yaml', $el);
my $yamlout = "$trd";
$yamlout =~ s/\s//g; # squash whitespace
is($yamlout,
   "---a:ab:'1'c:1d:truee:falsef:1.5g:-g1-g2h:a:ab:'1'c:1d:truee:false",
   "Correct YAML rendered");

# Other conversions
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{yesno_boolean}->(1),
   'yes',
   'yesno with true value');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{yesno_boolean}->(0),
   'no',
   'yesno with false value');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{YESNO_boolean}->(1),
   'YES',
   'YESNO with true value');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{YESNO_boolean}->(0),
   'NO',
   'YESNO with false value');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{singlequote_string}->("abc"),
   "'abc'",
   'singlequote');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{doublequote_string}->("abc"),
   '"abc"',
   'doublequote');

# Test with tiny, has to be single level hash
$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el);
my $tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   "a=ab=1c=1d=1e=0",
   "Correct Config::tiny without element options rendered");

$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'yesno' => 1, 'singlequote' => 1});
$tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   "a='a'b='1'c=1d=yese=no",
   "Correct Config::tiny with yesno and singlequote rendered");

$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'YESNO' => 1, 'doublequote' => 1});
$tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   'a="a"b="1"c=1d=YESe=NO',
   "Correct Config::tiny with YESNO and doublequote rendered");


done_testing;

