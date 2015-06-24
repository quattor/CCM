#
# test-element	Test class Element
#

use strict;
use warnings;

use POSIX qw (getpid);
use DB_File;
use Digest::MD5 qw(md5_hex);
use Test::More;

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Element;
use EDG::WP4::CCM::Path;

use Cwd;

use CCMTest qw(make_file);

my $cdtmp = getcwd()."/target/tmp";
mkdir($cdtmp) if (! -d $cdtmp);

#
# Generate an example of DBM file
#
sub gen_dbm ($$) {

    my ($cache_dir, $profile) = @_;
    my (%hash);
    my ($key, $val, $active);
    my ($derivation);

    # remove previous cache dir

    # create new profile
    mkdir("$cache_dir");
    mkdir("$cache_dir/$profile");
    mkdir("$cache_dir/$DATA_DN");

    make_file("$cache_dir/$GLOBAL_LOCK_FN", "no\n");
    make_file("$cache_dir/$CURRENT_CID_FN", "1\n");
    make_file("$cache_dir/$LATEST_CID_FN", "1\n");

    $active = $profile . "/active." . getpid();
    make_file("$cache_dir/$active", "1\n");

    tie(%hash, "DB_File", "${cache_dir}/${profile}/path2eid.db",
        &O_RDWR|&O_CREAT, 0644) or return();
    $key = "/path/to/property";
    $val = 0x00000001;
    $hash{$key} = pack("L", $val);
    $key = "/path/to/resource";
    $val = 0x00000002;
    $hash{$key} = pack("L", $val);
    untie(%hash);

    tie(%hash, "DB_File", "${cache_dir}/${profile}/eid2data.db",
        &O_RDWR|&O_CREAT, 0644) or return();
    # value
    $key = 0x00000001;
    $hash{pack("L", $key)} = "a string";
    # type
    $key = 0x10000001;
    $hash{pack("L", $key)} = "string";
    # derivation
    $key = 0x20000001;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L", $key)} = $derivation;
    # checksum
    $key = 0x30000001;
    $hash{pack("L", $key)} = md5_hex($derivation);
    # description
    $key = 0x40000001;
    $hash{pack("L", $key)} = "an example of string";

    # value
    $key = 0x00000002;
    $hash{pack("L", $key)} = "a list";
    # type
    $key = 0x10000002;
    $hash{pack("L", $key)} = "list";
    # derivation
    $key = 0x20000002;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L", $key)} = $derivation;
    # checksum
    $key = 0x30000002;
    $hash{pack("L", $key)} = md5_hex($derivation);
    # description
    $key = 0x40000002;
    $hash{pack("L", $key)} = "an example of list";

    untie(%hash);

    return (1);

}

my ($element, $property, $resource, $path);
my ($type, $derivation, $checksum, $description, $value);
my ($string);

my ($cm, $config, $cache_dir, $profile);
my ($prof_dir, $eid, $name);


$cache_dir = "$cdtmp/cm-element-test";
$profile = "profile.1";
ok(! -d $cache_dir, "Cachedir $cache_dir doesn't exist");

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

$cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
$config = EDG::WP4::CCM::Configuration->new($cm, 1, 1);

# create element with string path
$path = "/path/to/property";
$element = EDG::WP4::CCM::Element->new($config, $path);
isa_ok($element, "EDG::WP4::CCM::Element",
       "Element->new(config, string) is a EDG::WP4::CCM::Element instance");

# create element with Path object
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::Element->new($config, $path);
isa_ok($element, "EDG::WP4::CCM::Element",
       "Element->new(config, Path) is a EDG::WP4::CCM::Element instance");

# create resource with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/resource");
$element = EDG::WP4::CCM::Element->createElement($config, $path);
isa_ok($element, "EDG::WP4::CCM::Resource",
       "Element->createElement(config, Path_to_resource) is a EDG::WP4::CCM::Resource instance");

# create property with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::Element->createElement($config, $path);
isa_ok($element, "EDG::WP4::CCM::Property",
       "Element->createElement(config, Path_to_property) is a EDG::WP4::CCM::Property instance");

# test getEID()
$eid = $element->getEID();
is($eid, 1, "Element->getEID() 1");

# test getName()
$name = $element->getName();
is($name, "property", "Element->getName()");

# test getPath()
$path = $element->getPath();
$string = $path->toString();
is($string, "/path/to/property", "Element->getPath()");

# test getType()
$type = $element->getType();
is($type, EDG::WP4::CCM::Element->STRING, "Element->getType()" );

# test getDerivation()
$derivation = $element->getDerivation();
is($derivation, "lxplus.tpl,hardware.tpl,lxplust_025.tpl",
   "Element->getDerivation()");

# test getChecksum()
$checksum = $element->getChecksum();
is($checksum, md5_hex($derivation), "Element->getChecksum()");

# test getDescription()
$description = $element->getDescription();
is($description, "an example of string", "Element->getDescription()");

# test getValue()
$value = $element->getValue();
is($value, "a string", "Element->getValue()");

# test isType()
ok($element->isType(EDG::WP4::CCM::Element->STRING),
    "Element->isType(STRING)");
ok(!$element->isType(EDG::WP4::CCM::Element->LONG),
    "!Element->isType(LONG)");
ok(!$element->isType(EDG::WP4::CCM::Element->DOUBLE),
    "!Element->isType(DOUBLE)");
ok(!$element->isType(EDG::WP4::CCM::Element->BOOLEAN),
    "!Element->isType(BOOLEAN)");
ok(!$element->isType(EDG::WP4::CCM::Element->LIST),
    "!Element->isType(LIST)");
ok(!$element->isType(EDG::WP4::CCM::Element->NLIST),
    "!Element->isType(NLIST)");

# test isResource()
ok(!$element->isResource(),   "!Element->isResource()");

# test isProperty()
ok($element->isProperty(),   "Element->isProperty()");

#
# Test CCM::Configuration instance methods
#

# test getConfiguration()
$config = $element->getConfiguration();
$prof_dir  = $config->getConfigPath();
is($prof_dir, "$cache_dir/$profile", "Element->getConfiguration()");

$path = $element->getPath();

my $preppath = $config->_prepareElement("$path");
isa_ok($preppath, "EDG::WP4::CCM::Path",
       "_prepareElement returns EDG::WP4::CCM::Path instance");
is("$preppath", "$path", "_prepareElement path has expected value");

ok($config->elementExists("$path"), "config->elementExists true for path $path");
ok(! $config->elementExists("/fake$path"), "config->elementExists false for path /fake$path");

my $cfg_el = $config->getElement("$path");
my $pathdata = 'a string';

isa_ok($cfg_el, "EDG::WP4::CCM::Element",
       "config->getElement returns EDG::WP4::CCM::Element instance");
# is a property, not a hash or list
is($cfg_el->getValue(), $pathdata, "getVale from element instance as expected");
is_deeply($cfg_el->getTree(), $pathdata, "getTree from element instance as expected");

is($config->getValue("$path"), $pathdata, "config->getValue of $path as expected");
# is a property, not a hash or list
is_deeply($config->getTree("$path"), $pathdata, "config->getTree of $path as expected");
ok(! defined($config->getTree("/fake$path")), "config->getTree of /fake$path undefined");

done_testing();
