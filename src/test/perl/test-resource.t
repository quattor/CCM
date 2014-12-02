#
# test-resource.pl	Test class Resource
#

use strict;
use warnings;

use POSIX qw (getpid);
use DB_File;
use Digest::MD5 qw(md5_hex);
use Test::Simple tests => 42;
use LC::Exception qw(SUCCESS throw_error);

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Element;
use EDG::WP4::CCM::Resource;
use EDG::WP4::CCM::Path;

use myTest qw (eok make_file);

my ($resource, $path, $string, $type);
my ($derivation, $checksum, $description, $value);

my ($cm, $config, $cache_dir, $profile, %hash, $key, @array, $i, $name);

my $tmp;

my $ec = LC::Exception::Context->new->will_store_errors;

use Cwd;
my $cdtmp = getcwd()."/target/tmp";
mkdir($cdtmp) if (! -d $cdtmp);

# TODO: Use Test::More and t::Test

#
# Generate an example of DBM file
#
sub gen_dbm ($$) {

    my ($cache_dir, $profile) = @_;
    my (%hash);
    my ($key, $val, $active);

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

    $key = "/path/to/list";
    $value = 0x00000001;
    $hash{$key} = pack("L",$value);

    $key = "/path/to/list/0";
    $value = 0x00000002;
    $hash{$key} = pack("L",$value);

    $key = "/path/to/list/1";
    $value = 0x00000003;
    $hash{$key} = pack("L",$value);

    $key = "/path/to/nlist";
    $value = 0x00000004;
    $hash{$key} = pack("L",$value);

    $key = "/path/to/nlist/zero";
    $value = 0x00000005;
    $hash{$key} = pack("L",$value);

    $key = "/path/to/nlist/one";
    $value = 0x00000006;
    $hash{$key} = pack("L",$value);

    untie(%hash);

    tie(%hash, "DB_File", "${cache_dir}/${profile}/eid2data.db",
        &O_RDWR|&O_CREAT, 0644) or return();

    # value
    $key = 0x00000001;
    $hash{pack("L",$key)} = chr(48).chr(0).chr(49);
    # type
    $key = 0x10000001;
    $hash{pack("L",$key)} = "list";
    # derivation
    $key = 0x20000001;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000001;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000001;
    $hash{pack("L",$key)} = "an example of list";

    # value
    $key = 0x00000002;
    $hash{pack("L",$key)} = "element 0";
    # type
    $key = 0x10000002;
    $hash{pack("L",$key)} = "string";
    # derivation
    $key = 0x20000002;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000002;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000002;
    $hash{pack("L",$key)} = "an example of string";

    # value
    $key = 0x00000003;
    $hash{pack("L",$key)} = "element 1";
    # type
    $key = 0x10000003;
    $hash{pack("L",$key)} = "string";
    # derivation
    $key = 0x20000003;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000003;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000003;
    $hash{pack("L",$key)} = "an example of string";

    # value
    $key = 0x00000004;
    $hash{pack("L",$key)} = $hash{pack("L",$key)} =
       chr(122).chr(101).chr(114).chr(111).chr(0).chr(111).chr(110).chr(101);

    # type
    $key = 0x10000004;
    $hash{pack("L",$key)} = "nlist";
    # derivation
    $key = 0x20000004;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000004;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000004;
    $hash{pack("L",$key)} = "an example of nlist";

    # value
    $key = 0x00000005;
    $hash{pack("L",$key)} = "element zero";
    # type
    $key = 0x10000005;
    $hash{pack("L",$key)} = "string";
    # derivation
    $key = 0x20000005;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000005;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000005;
    $hash{pack("L",$key)} = "an example of string";

    # value
    $key = 0x00000006;
    $hash{pack("L",$key)} = "element one";
    # type
    $key = 0x10000006;
    $hash{pack("L",$key)} = "string";
    # derivation
    $key = 0x20000006;
    $derivation = "lxplus.tpl,hardware.tpl,lxplust_025.tpl";
    $hash{pack("L",$key)} = $derivation;
    # checksum
    $key = 0x30000006;
    $hash{pack("L",$key)} = md5_hex($derivation);;
    # description
    $key = 0x40000006;
    $hash{pack("L",$key)} = "an example of string";

    untie(%hash);

    return (1);

}

#
# Perform tests
#
$cache_dir = "$cdtmp/cm-element-test";
$profile = "profile.1";
ok(! -d $cache_dir, "Cachedir $cache_dir doesn't exist");

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

$cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
$config = EDG::WP4::CCM::Configuration->new($cm, 1, 1);

# create resource type list

$path = EDG::WP4::CCM::Path->new("/path/to/list");
$resource = EDG::WP4::CCM::Resource->new($config, $path);
ok(defined($resource) && UNIVERSAL::isa($resource,
                         "EDG::WP4::CCM::Resource"),
                         "Resource->new(config, Path)");

#
# validate inheritance of Element methods
#

# test getPath()
$path = $resource->getPath();
$string = $path->toString();
ok($string eq "/path/to/list", "Resource->getPath()");

# test getType()
$type = $resource->getType();
ok($type == EDG::WP4::CCM::Resource->LIST, "Resource->getType()");

# test getDerivation()
$derivation = $resource->getDerivation();
ok($derivation eq "lxplus.tpl,hardware.tpl,lxplust_025.tpl",
   "Resource->getDerivation()");

# test getChecksum()
$checksum = $resource->getChecksum();
ok($checksum eq md5_hex($derivation), "Resource->getChecksum()");

# test getDescription()
$description = $resource->getDescription();
ok($description eq "an example of list", "Resource->getDescription()");

# test getValue()
$value = $resource->getValue();
ok($value eq chr(48).chr(0).chr(49), "Resource->getValue()");

# test isType()
ok(!$resource->isType(EDG::WP4::CCM::Resource->STRING),
    "Resource->isType(STRING)");
ok(!$resource->isType(EDG::WP4::CCM::Resource->LONG),
    "!Resource->isType(LONG)");
ok(!$resource->isType(EDG::WP4::CCM::Resource->DOUBLE),
    "!Resource->isType(DOUBLE)");
ok(!$resource->isType(EDG::WP4::CCM::Resource->BOOLEAN),
    "!Resource->isType(BOOLEAN)");
ok($resource->isType(EDG::WP4::CCM::Resource->LIST),
    "Resource->isType(LIST)");
ok(!$resource->isType(EDG::WP4::CCM::Resource->NLIST),
    "!Resource->isType(NLIST)");

# test isResource()
ok($resource->isResource(),   "Resource->isResource()");

# test isProperty()
ok(!$resource->isProperty(),   "!Resource->isProperty()");

#
# test Resource specific methods
#

# test getList()

@array = $resource->getList();
ok($#array == 1, "Resource->getList()");

ok($array[0]->getValue() eq "element 0", "Resource->getList()[0] element 0");
ok($array[1]->getValue() eq "element 1", "Resource->getList()[1] element 1");

# test hasNextElement(), getNextElement(),
#      getCurrentElemnt() and currentElementName()

ok($resource->hasNextElement(), "Resource->hasNextElement()");
ok($resource->getNextElement()->getValue() eq "element 0",
        "Resource->getNextElement() element 0");
ok($resource->getCurrentElement()->getValue() eq "element 0",
        "Resource->getCurrentElement() element 0");
#ok($resource->currentElementName() eq "0",
#        "Resource->currentElementName() element 0");
ok($resource->hasNextElement(), "Resource->hasNextElement()");
ok($resource->getNextElement()->getValue() eq "element 1",
        "Resource->getNextElement() element 1");
ok($resource->getCurrentElement()->getValue() eq "element 1",
        "Resource->getCurrentElement() element 1");
#ok($resource->currentElementName() eq "1",
#        "Resource->currentElementName() element 1");
ok(!$resource->hasNextElement(), "!Resource->hasNextElement()");

# test reset()

ok($resource->reset(), "Resource->reset()");
#eok($ec, $name = $resource->currentElementName(),
#         "Resource->currentElementName()");
ok($resource->getNextElement()->getValue() eq "element 0",
         "Resource->getNextElement() element 0");
#ok($resource->currentElementName() eq "0", "Resource->currentElementName()");

# create resource type nlist

$path = EDG::WP4::CCM::Path->new("/path/to/nlist");
$resource = EDG::WP4::CCM::Resource->new($config, $path);
ok(defined($resource) && UNIVERSAL::isa($resource,
                         "EDG::WP4::CCM::Resource"),
                         "Resource->new(config, Path)");

# test getHash()

%hash = $resource->getHash();
ok(scalar(keys(%hash)) == 2, "Resource->getHash()");

foreach $key (keys %hash) {
    ok($hash{$key}->getName() eq $key,
       "Resource->Hash() element $key");
}

# test hasNextElement(), getNextElement(),
#      currentElemnt() and currentElementName()

ok($resource->hasNextElement(), "Resource->hasNextElement()");
ok($resource->getNextElement()->getValue() eq "element zero",
        "Resource->getNextElement() element zero");
ok($resource->getCurrentElement()->getValue() eq "element zero",
        "Resource->getCurrentElement() element zero");
#ok($resource->currentElementName() eq "zero",
#        "Resource->currentElementName() element zero");
ok($resource->hasNextElement(), "Resource->hasNextElement()");
ok($resource->getNextElement()->getValue() eq "element one",
        "Resource->getNextElement() element one");
ok($resource->getCurrentElement()->getValue() eq "element one",
        "Resource->getCurrentElement() element one");
#ok($resource->currentElementName() eq "one",
#        "Resource->currentElementName() element one");
ok(!$resource->hasNextElement(), "!Resource->hasNextElement()");

# test reset()

ok($resource->reset(), "Resource->reset()");
#eok($ec, $name = $resource->currentElementName(),
#         "Resource->currentElementName()");
ok($resource->getNextElement()->getValue() eq "element zero",
         "Resource->getNextElement() element zero");
#ok($resource->currentElementName() eq "zero",
#   "Resource->currentElementName()");

