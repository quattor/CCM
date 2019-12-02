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
use Test::Quattor qw(tt-scalar);
use EDG::WP4::CCM::TextRender;
use EDG::WP4::CCM::TextRender::Scalar qw(%ELEMENT_TYPES);
use Test::Quattor::RegexpTest;
use Cwd;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

# Test exported readonly property type names
is($ELEMENT_TYPES{BOOLEAN}, 'BOOLEAN', 'ELEMENT_TYPES BOOLEAN exported');
is($ELEMENT_TYPES{STRING}, 'STRING', 'ELEMENT_TYPES STRING exported');
is($ELEMENT_TYPES{DOUBLE}, 'DOUBLE', 'ELEMENT_TYPES DOUBLE exported');
is($ELEMENT_TYPES{LONG}, 'LONG', 'ELEMENT_TYPES LONG exported');

=pod

=head2 Test basic class methods

=cut

my $arb = 'arbitrarytext';
my $arbt = 'ARBITRARY';
my $sc_arb = EDG::WP4::CCM::TextRender::Scalar->new($arb, $arbt);
isa_ok($sc_arb, "EDG::WP4::CCM::TextRender::Scalar",
       "EDG::WP4::CCM::TextRender::Scalar instance created");
is($sc_arb->{VALUE}, $arb, "VALUE attribute found");
is($sc_arb->{TYPE}, $arbt, "TYPE attribute found");
is("$sc_arb", "$arb", "Stringification returns VALUE in string context");
is($sc_arb->get_type(), $arbt, "TYPE attribute found");
is($sc_arb->get_value(), $arb, "value / VALUE attribute returned");
ok(! $sc_arb->is_boolean(), "ARBITRARY is not a boolean");
ok(! $sc_arb->is_string(), "ARBITRARY is not a string");
ok(! $sc_arb->is_double(), "ARBITRARY is not a double");
ok(! $sc_arb->is_long(), "ARBITRARY is not a long");

# inject types
$sc_arb->{TYPE} = $ELEMENT_TYPES{BOOLEAN};
ok($sc_arb->is_boolean(), "$ELEMENT_TYPES{BOOLEAN} is a boolean");
$sc_arb->{TYPE} = $ELEMENT_TYPES{STRING};
ok($sc_arb->is_string(), "$ELEMENT_TYPES{STRING} is a string");
$sc_arb->{TYPE} = $ELEMENT_TYPES{DOUBLE};
ok($sc_arb->is_double(), "$ELEMENT_TYPES{DOUBLE} is a double");
$sc_arb->{TYPE} = $ELEMENT_TYPES{LONG};
ok($sc_arb->is_long(), "$ELEMENT_TYPES{LONG} is a long");

# restore
$sc_arb->{TYPE} = 'ARBITRARY';

# Test the TT Text VMethods
# Test the ones from TT with EL5
my @vmethods = qw(item list hash length size defined match search repeat replace remove split chunk substr);
foreach my $vm (@vmethods) {
    ok($sc_arb->can($vm), "VMethod $vm available in CCM::TextRender::Scalar instance");
}

=pod

=head2 Test scalar operations

=cut

my $true = EDG::WP4::CCM::TextRender::Scalar->new(1, $ELEMENT_TYPES{BOOLEAN});
ok($true->is_boolean(), "is a boolean");
ok($true, "is a boolean and is true");

my $false = EDG::WP4::CCM::TextRender::Scalar->new(0, $ELEMENT_TYPES{BOOLEAN});
ok($true->is_boolean(), "is a boolean");
ok(! $false, "is a boolean and is false");

my $double = EDG::WP4::CCM::TextRender::Scalar->new(1.5, $ELEMENT_TYPES{DOUBLE});
ok($double->is_double(), "is a double");
is($double, 1.5, "is a double and has correct value");
is(1 + $double, 2.5, "is a double and has correct left addition (numify/0+)");
is($double + 1, 2.5, "is a double and has correct right addition (+; with fallback to numify)");
is(1 - $double, -0.5, "is a double and has correct left subtract");
is($double - 1, 0.5, "is a double and has correct right subtract");
is(3 * $double, 4.5, "is a double and has correct left multiply");
is($double * 3, 4.5, "is a double and has correct right multiply");
is(4.5 / $double, 3 , "is a double and has correct left division");
is($double / 3, 0.5, "is a double and has correct right division");

my $doubleonezero = EDG::WP4::CCM::TextRender::Scalar->new(1, $ELEMENT_TYPES{DOUBLE});
ok($doubleonezero == 1, "is a double and has correct value");
ok($doubleonezero == 1.0, "is a double and has correct value with trailing .0 (perl does not care)");
ok($doubleonezero eq "1.0", "is a double and has correct string value as string");
# is uses left.compare(right), so eq instead of == here
is("$doubleonezero", "1.0", "is a double and has correct string repr with trailing .0 ");

my $long = EDG::WP4::CCM::TextRender::Scalar->new(2, $ELEMENT_TYPES{LONG});
ok($long->is_long(), "is a long");
is($long, 2, "is a long and has correct value");
is(1 + $long, 3, "is a long and has correct left addition (numify/0+)");
is($long + 1, 3, "is a long and has correct right addition (+; with fallback to numify)");
is(1 - $long, -1, "is a long and has correct left subtract");
is($long - 1, 1, "is a long and has correct right subtract");
is(3 * $long, 6, "is a long and has correct left multiply");
is($long * 3, 6, "is a long and has correct right multiply");
is(4.5 / $long, 2.25 , "is a long and has correct left division");
is($long / 4, 0.5, "is a long and has correct right division");

# combine instances
is($long + $double, 3.5, "Addition of instances ok");
is($long * $double, 3, "Multiplication of instances ok");
is($long - $double, 0.5, "Subtraction of instances ok");
is($double / $long, 0.75, "Division of instances ok");

# compare
ok($long > 1, "long numeric right compare");
ok($long == 2, "long string right equality");
ok($long eq "2", "long string right compare");
ok(3 > $double, "double numeric left compare");
ok($double == 1.5, "double numeric left compare");
ok($double eq "1.5", "double string left compare");
ok($long > $double, "numeric instance compare");
ok(!($double > $long), "numeric instance compare inverted");

=pod

=head2 Test element rendering

=cut

my $el = {
    arbitrary => $sc_arb,
    true => $true,
    false => $false,
    double => $double,
    long => $long,
};

my $trd = EDG::WP4::CCM::TextRender->new(
    'tt-scalar',
    $el,
    includepath => getcwd()."/src/test/resources",
    relpath => 'rendertest',
    eol => 0,
    );
is($trd->{fail}, undef, "Fail is undefined with new variables ".($trd->{fail} || "<undef>"));

my $rt = Test::Quattor::RegexpTest->new(
    regexp => 'src/test/resources/rendertest/regexptest-tt-scalar',
    text => "$trd",
);
$rt->test();

diag("$trd");


done_testing();
