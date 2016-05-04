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
use Test::Quattor qw(textrender textrender_adv);
use EDG::WP4::CCM::TextRender;
use Test::Quattor::RegexpTest;
use Test::Quattor::TextRender::Base;
use Cwd;

use Config::General;

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
my $cfg_adv = get_config_for_profile("textrender_adv");
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
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{truefalse_boolean}->(1),
   'true',
   'truefalse with true value');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{truefalse_boolean}->(0),
   'false',
   'truefalse with false value');
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

# Test xml stringification
ok(EDG::WP4::CCM::TextRender::_is_valid_xml("text"), "'text' is valid xml string");
ok(EDG::WP4::CCM::TextRender::_is_valid_xml("<![CDATA[text]]>"), "CDATA 'text' is valid xml string");

ok(! EDG::WP4::CCM::TextRender::_is_valid_xml("text < othertext"), "'text < othertext' is not valid xml string");
ok(EDG::WP4::CCM::TextRender::_is_valid_xml("text &gt; othertext"), "'text &gt; othertext' is not valid xml string");
ok(EDG::WP4::CCM::TextRender::_is_valid_xml("<![CDATA[text < othertext]]>"), "CDATA 'text < othertext' is valid xml string");

is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{xml_primitive_string}->("my text"),
   "my text", "Correct conversion to valid xml 'my text'");

is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{xml_primitive_string}->("my text < othertext"),
   "<![CDATA[my text < othertext]]>", "Correct conversion to valid xml 'my text < othertext'");

is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{xml_primitive_string}->("my text ]]> < othertext ]]>"),
   "<![CDATA[my text ]]>]]&gt;<![CDATA[ < othertext ]]>]]&gt;<![CDATA[]]>",
   "Correct conversion to valid xml 'my text ]]> < othertext ]]>'");

is(&$EDG::WP4::CCM::TextRender::_arrayref_join(undef, ';'), '', '_arrayef_join with undef returns empty string');
is(&$EDG::WP4::CCM::TextRender::_arrayref_join([], ';'), '', '_arrayef_join with empty arrayref returns empty string');
is(&$EDG::WP4::CCM::TextRender::_arrayref_join([1,undef,'b'], ';'), '1;;b', '_arrayef_join with scalar arrayref returns joined string');
is_deeply(&$EDG::WP4::CCM::TextRender::_arrayref_join([[1,2],2,{a=>'b'}], ';'),
          [[1,2],2,{a=>'b'}],
          '_arrayef_join with non-salar first element retrun original arrayref');

is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{arrayref_join_comma}->(["abc", undef, 1]),
   'abc,,1',
   'comma separated arrayref');
is($EDG::WP4::CCM::TextRender::ELEMENT_CONVERT{arrayref_join_space}->(["abc", undef, 1]),
   'abc  1',
   'space separated arrayref');

# Test with tiny, has to be single level hash
$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el);
my $tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   "a=ab=1c=1d=1e=0",
   "Correct Config::Tiny without element options rendered");

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
   "Correct Config::Tiny with yesno and singlequote rendered");

$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'YESNO' => 1, 'doublequote' => 1});
$tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   'a="a"b="1"c=1d=YESe=NO',
   "Correct Config::Tiny with YESNO and doublequote rendered");

$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'truefalse' => 1});
$tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   'a=ab=1c=1d=truee=false',
   "Correct Config::Tiny with truefalse rendered");

$el = $cfg->getElement("/h");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'TRUEFALSE' => 1});
$tinyout = "$trd";
$tinyout =~ s/\s//g; # squash whitespace
is($tinyout,
   'a=ab=1c=1d=TRUEe=FALSE',
   "Correct Config::Tiny with TRUEFALSE rendered");

# cannot use regular $cfg->getElement("/g"),
# as getTree will squash this to a scalar, and tiny expected a hashref
$el = $cfg_adv->getElement("/a");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'joincomma' => 1});
is("$trd", "a=x,y\n", "Correct Config::Tiny with joincomma rendered");

# deepest list is first squashed to string,
# so the list of list becomes a list of strings,
# and then a space-separated list of space-spearated list of strings
$el = $cfg_adv->getElement("/b");
$trd = EDG::WP4::CCM::TextRender->new('tiny', $el, element => {'joinspace' => 1});
is("$trd", "b=k l m n\n", "Correct Config::Tiny with joinspace rendered");

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
is(ref($trd->{contents}), 'HASH',
    "contents is a HASH reference");

my $rt = Test::Quattor::RegexpTest->new(
    regexp => 'src/test/resources/rendertest/regexptest-extravars',
    text => "$trd",
);
$rt->test();

diag("$trd");
diag explain $trd->{contents};

# add additional test for scalar string
$el = $cfg->getElement("/a");

my $trd_s = EDG::WP4::CCM::TextRender->new(
    'extravars_scalar',
    $el,
    includepath => getcwd()."/src/test/resources",
    relpath => 'rendertest',
    eol => 0,
    );
is($trd_s->{fail}, undef, "Fail is undefined with new variables (scalar string) ".($trd->{fail} || "<undef>"));
is_deeply($trd_s->{contents}, {}, "empty hashref as contents for scalar string/non-hashref contents");
is(ref($trd_s->{ttoptions}->{VARIABLES}->{CCM}->{contents}), 'EDG::WP4::CCM::TT::Scalar',
   "scalar contents via CCM.contents is EDG::WP4::CCM::TT::Scalar");

$rt = Test::Quattor::RegexpTest->new(
    regexp => 'src/test/resources/rendertest/regexptest-extravars-scalar_string',
    text => "$trd_s",
);
$rt->test();

diag("$trd_s");
diag explain $trd_s->{contents};

# add additional test for arrayref
$el = $cfg->getElement("/g");

$trd_s = EDG::WP4::CCM::TextRender->new(
    'extravars_list',
    $el,
    includepath => getcwd()."/src/test/resources",
    relpath => 'rendertest',
    eol => 0,
    );
is($trd_s->{fail}, undef, "Fail is undefined with new variables (list) ".($trd->{fail} || "<undef>"));
is_deeply($trd_s->{contents}, {}, "empty hashref as contents for list/non-hashref contents");
is_deeply($trd_s->{ttoptions}->{VARIABLES}->{CCM}->{contents}, [qw(g1 g2)],
    "list contents via CCM.contents as expected");

$rt = Test::Quattor::RegexpTest->new(
    regexp => 'src/test/resources/rendertest/regexptest-extravars-list',
    text => "$trd_s",
);
$rt->test();

diag("$trd_s");
diag explain $trd_s->{contents};

=pod

=head2 general alias

Test general as alias for CCM/general, validate C<Config::General> format

=cut

my $caf_trd = mock_textrender();


my $contents = {
    'name_level0' => 'scalar_level0',
    'level1' => {
        'name_level1' => 'scalar_level1',
        'name_level2' => [
            'scalar_element0',
            'scalar_element1',
            ]
        },
    "level2 space", {
        'more' => 'values',
        'name2_level2' => [
            { 'l2_more' => 'l2 values'},
            { 'l2_moreb' => 'l2_moreb'},
            ]
        },
};

$trd = EDG::WP4::CCM::TextRender->new('general', $contents);
is($trd->{module}, 'general', 'module general is alias for CCM/general (relative module name ok)');
is($trd->{relpath}, 'CCM', 'module general is alias for CCM/general (relpath ok)');
ok($trd->{method_is_tt}, "method_is_tt is true for module general");

my $txt = "$trd";
$txt =~ s/\s+//g; # squash whitespace
# the correctnes is verified in detail in the TT unittests
is($txt,
   '<"level1">name_level1scalar_level1name_level2scalar_element0name_level2scalar_element1</"level1"><"level2space">morevalues<"name2_level2">l2_morel2values</"name2_level2"><"name2_level2">l2_morebl2_moreb</"name2_level2"></"level2space">name_level0scalar_level0',
   "general / CCM/general module rendered correctly");

# No error logging in the module
ok(! exists($trd->{fail}), "No errors logged anywhere");

my %cg_cfg = Config::General->new(-String => "$trd")->getall();
is_deeply(\%cg_cfg, $contents, "Correctly rendered valid Config::General");
diag explain \%cg_cfg;

done_testing;
