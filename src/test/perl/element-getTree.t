#
# element-getTree Test class Element methods to retrieve data via getTree
#

use strict;
use warnings;

use Test::More;

use Test::Quattor qw(element_test);

my $cfg = get_config_for_profile("element_test");

my $el = $cfg->getElement("/");

isa_ok($el, "EDG::WP4::CCM::Element", "Got element");
is($el->getPath()->toString(), "/", "Element path is /");

# TODO replace stringified values with actual data
my $rt = $el->getTree();
my @rt_keys = sort keys %$rt;
is_deeply($rt, {
    a => ["1", "2", "3"],
    b => "hello",
    c => "1.5",
    d => 1,
    e => { 
        f => "1" 
    },
    g => [ 
        [ '1', '2'], 
        [ '3', '4'], 
    ],
    h => [ 
        { a => '10', b => '11' }, 
        { a => '12' },
    ],
}, "getTree /");

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


done_testing();
