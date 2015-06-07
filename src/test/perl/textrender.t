use strict;
use warnings;

use Test::More;

use EDG::WP4::CCM::CCfg;
use B;

BEGIN {
    # Force typed json for improved testing
    # Use BEGIN to make sure it is executed before the import from Test::Quattor
    ok(EDG::WP4::CCM::CCfg::_setCfgValue('json_typed', 1), 'json_typed enabled');
}

use Readonly;
use Test::Quattor qw(textrender);
use EDG::WP4::CCM::TextRender;
use Test::Quattor::RegexpTest;
use Cwd;

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

isa_ok($trd->{ttoptions}->{VARIABLES}->{CCM}->{element}->{path},
       "EDG::WP4::CCM::Path",
       "path is a CCM::Path instance");
is("$trd->{ttoptions}->{VARIABLES}->{CCM}->{element}->{path}", '/',
   "Correct path /");

# extra_vars
# calls are tested via TT tests
my @extra_vars = sort keys %{$trd->{ttoptions}->{VARIABLES}->{CCM}};
is_deeply(\@extra_vars,
          ['contents', 'element', 'escape', 'is_hash', 'is_list', 'is_scalar', 'ref', 'unescape'],
          "Correct CCM VARIABLES keys");
my @extra_el_vars = sort keys %{$trd->{ttoptions}->{VARIABLES}->{CCM}->{element}};
is_deeply(\@extra_el_vars,
          ['path'],
          "Correct CCM VARIABLES element keys");

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
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{upper}->('abcdef'),
   'ABCDEF',
   'upper returns uppercase strings');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{lower}->('ABCDEF'),
   'abcdef',
   'lower returns lowercase strings');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{singlequote_string}->("abc"),
   "'abc'",
   'singlequote');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{doublequote_string}->("abc"),
   '"abc"',
   'doublequote');

# Test the cast methods
my $string = $EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{cast_string}->(100);
ok(! B::svref_2object(\$string)->isa("B::IV"), 'cast string of integer is no integer anymore');
ok(B::svref_2object(\$string)->isa("B::PV"), 'cast string of integer is a string');
# Run this lasts, who knows what the test framework does with it
# that could change the internal representation
is($string, "100", 'cast string returns correct value');

my $long = $EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{cast_long}->("100");
ok(! B::svref_2object(\$long)->isa("B::PV"), 'cast long of string is no string anymore');
ok(B::svref_2object(\$long)->isa("B::IV"), 'cast long of string is an integer');
# Run this lasts, who knows what the test framework does with it
# that could change the internal representation
is($long, 100, 'cast long returns correct value');

my $double = $EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{cast_double}->("10.0");
ok(! B::svref_2object(\$double)->isa("B::PV"), 'cast double of string is no string anymore');
ok(B::svref_2object(\$double)->isa("B::NV"), 'cast double of string is a double');
# Run this lasts, who knows what the test framework does with it
# that could change the internal representation
is($double, 10.0, 'cast double returns correct value');

my $boolean = $EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{cast_boolean}->(0);
# can't really test if it it an integer anymore via isa('B::IV'); but an integer is no PVNV
ok(B::svref_2object(\$boolean)->isa("B::PVNV"), 'cast boolean of integer 0 is a boolean');
# Run this lasts, who knows what the test framework does with it
# that could change the internal representation
ok(! $boolean, 'cast boolean returns correct value false');

$boolean = $EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{cast_boolean}->(1);
# can't really test if it it an integer anymore via isa('B::IV'); but an integer is no PVNV
ok(B::svref_2object(\$boolean)->isa("B::PVNV"), 'cast boolean of integer 1 is a boolean');
# Run this lasts, who knows what the test framework does with it
# that could change the internal representation
ok($boolean, 'cast boolean returns correct value true');

# Test with tiny, has to be single level hash
$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el);
my $tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   "a=ab=1c=1d=1e=0",
   "Correct Config::tiny without element options rendered");

isa_ok($trd->{ttoptions}->{VARIABLES}->{CCM}->{element}->{path},
       "EDG::WP4::CCM::Path",
       "path is a CCM::Path instance");
is("$trd->{ttoptions}->{VARIABLES}->{CCM}->{element}->{path}", '/h',
   "Correct path /h");

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

=pod

=head2 Extra TT options

Test the extra TT vars and methods

=cut

$el = $cfg->getElement("/");
$trd = EDG::WP4::CCM::TextRender->new(
    'extravars',
    $el,
    includepath => getcwd()."/src/test/resources",
    relpath => 'rendertest',
    eol => 0,
    );
is($trd->{fail}, undef, "Fail is undefined with new variables ".($trd->{fail} || "<undef>"));

my $rt = Test::Quattor::RegexpTest->new(
    regexp => 'src/test/resources/rendertest/regexptest-extravars',
    text => "$trd",
);
$rt->test();

diag("$trd");
diag explain $trd->{contents};

done_testing;

