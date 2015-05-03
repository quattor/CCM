#
# element-getTree Test class Element methods to retrieve data via getTree
#

use strict;
use warnings;

use Test::More;

use EDG::WP4::CCM::CCfg;

BEGIN {
    # Force typed json for improved testing
    # Use BEGIN to make sure it is executed before the import from Test::Quattor
    ok(EDG::WP4::CCM::CCfg::_setCfgValue('json_typed', 1), 'json_typed enabled');
}

use Test::Quattor qw(element_test);
use Readonly;
use JSON::XS;

ok(EDG::WP4::CCM::CCfg::getCfgValue('json_typed'), 'json_typed (still) enabled');

Readonly::Hash my %TREE => {
    a => ["1", "2", "3"],
    b => "hello",
    c => 1.5,
    d => 1,
    e => {
        f => 1,
        ff => 0,
    },
    g => [
        [ '1', 2],
        [ '3', 4],
    ],
    h => [
        { a => 10, b => '11' },
        { a => 12 },
    ]
};

Readonly::Hash my %CONVTREE => {
    a => ['"1"', '"2"', '"3"'],
    b => '"hello"',
    c => 'DOUBLE(1.5)',
    d => 'TRUE',
    e => {
        f => 'LONG(1)',
        ff => 'FALSE',
    },
    g => [
        [ '"1"', 'LONG(2)'],
        [ '"3"', 'LONG(4)'],
    ],
    h => [
        { a => 'LONG(10)', b => '"11"' },
        { a => 'LONG(12)' },
    ]
};


my $cfg = get_config_for_profile("element_test");

my $el = $cfg->getElement("/");

isa_ok($el, "EDG::WP4::CCM::Element", "Got element");
is($el->getPath()->toString(), "/", "Element path is /");

# TODO replace stringified values with actual data
my $rt = $el->getTree();
my @rt_keys = sort keys %$rt;
is_deeply($rt, \%TREE, "getTree /");

# need to "rewind"
$el = $cfg->getElement("/");
my $lvl0 = $el->getTree(0);
isa_ok($lvl0, "EDG::WP4::CCM::Element", "Got element for level 0");
is_deeply($lvl0->getTree, $rt, "lvl0->getTree return same as roottree");

my $g = $cfg->getElement("/g");
isa_ok($g, "EDG::WP4::CCM::Element", "Got element path=g");

# rewind
$el = $cfg->getElement("/");
my $lvl1 = $el->getTree(1);
my @lvl1_keys = sort keys %$lvl1;
is_deeply(\@rt_keys, \@lvl1_keys, "Same keys depth=1 as root");
isa_ok($lvl1->{g}, "EDG::WP4::CCM::Element", "Got element for path=g on level 1");
is_deeply($lvl1->{g}, $g, "element for path=g on level 1 is element path=g");

is_deeply($lvl1->{g}->getTree, $rt->{g}, "getTree of lvl1 key=g returns same as roottree key=g ");

# test conversion
$el = $cfg->getElement("/");
my $newtree = $el->getTree(undef,
                           convert_boolean => [sub {
                               my $value = shift;
                               return $value ? "true" : "false";
                           }, sub {
                               my $value = shift;
                               return uc $value;
                           }],
                           convert_string => [sub {
                               my $value = shift;
                               return "$value";
                           }, sub {
                               my $value = shift;
                               return "\"$value\"";
                           }],
                           convert_long => [sub {
                               my $value = shift;
                               return 0 + $value;
                           }, sub {
                               my $value = shift;
                               my $long = B::svref_2object(\$value)->isa("B::IV") ? "" : "NO";
                               return "${long}LONG($value)";
                           }],
                           convert_double => [sub {
                               my $value = shift;
                               return 0.0 + $value;
                           }, sub {
                                my $value = shift;
                                my $long = B::svref_2object(\$value)->isa("B::NV") ? "" : "NO";
                                return "${long}DOUBLE($value)";
                           }],
    );
is_deeply($newtree, \%CONVTREE, "getTree with properties converted");

# Test JSON formatted tree
$el = $cfg->getElement("/");
my $jsontree = $el->getTree(undef,
                            convert_boolean => [sub {
                                my $value = shift;
                                return $value ? \1 : \0;
                            }],
                            convert_string => [sub {
                                my $value = shift;
                                return "$value";
                            }],
                            convert_long => [sub {
                                my $value = shift;
                                return 0 + $value;
                            }],
                            convert_double => [sub {
                                my $value = shift;
                                return 0.0 + $value;
                            }],
    );

my $profile = "target/test/profiles/element_test.json";
ok(-f $profile, "Found element_test.json profile");

open FILE, $profile or die "Couldn't open profile $profile: $!";
my $profiletxt = join("", <FILE>);
$profiletxt =~ s/\s//g; # squash all whitespace
close FILE;

# panc produces pretty and key-sorted json, but 2 space indentation
is(JSON::XS->new->pretty(0)->canonical(1)->encode($jsontree), $profiletxt, "Reproduced JSON compliant");


done_testing();
