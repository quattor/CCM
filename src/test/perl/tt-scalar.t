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
use EDG::WP4::CCM::TT::Scalar qw(%ELEMENT_TYPES);
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
my $sc_arb = EDG::WP4::CCM::TT::Scalar->new($arb, 'ARBITRARY');
isa_ok($sc_arb, "EDG::WP4::CCM::TT::Scalar",
       "EDG::WP4::CCM::TT::Scalar instance created");
is($sc_arb->{VALUE}, $arb, "VALUE attribute found");
is($sc_arb->{TYPE}, 'ARBITRARY', "TYPE attribute found");
is("$sc_arb", "$arb", "Stringification returns VALUE in string context");
is($sc_arb->get_type(), 'ARBITRARY', "TYPE attribute found");
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
    ok($sc_arb->can($vm), "VMethod $vm available in CCM::TT::Scalar instance");
}

=pod

=head2 Test element rendering

=cut

my $el = {
    arbitrary => $sc_arb,
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
