# Test class Element default Property behaviour

use strict;
use warnings;

use POSIX qw (getpid);
use DB_File;
use Digest::MD5 qw(md5_hex);
use Test::More;
use LC::Exception qw(SUCCESS throw_error);

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Element;
use EDG::WP4::CCM::Path;

use CCMTest qw (eok make_file);

my $ec = LC::Exception::Context->new->will_store_errors;

use Cwd;
my $cdtmp = getcwd()."/target/property";
mkdir($cdtmp) if (! -d $cdtmp);

# Generate an example of DBM file
sub gen_dbm
{
    my ($cache_dir, $profile) = @_;
    my (%hash);
    my ($key, $val, $active);
    my ($derivation);

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
    $key = "/path/to/element";
    $val = 0x00000001;
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
    untie(%hash);

    return (SUCCESS);
}

# Perform tests
my $cache_dir = "$cdtmp/property-test";
my $profile = "profile.1";
ok(! -d $cache_dir, "Cachedir $cache_dir doesn't exist");

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

my $cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
my $config = EDG::WP4::CCM::Configuration->new($cm, 1, 1);

# create property
my $path = EDG::WP4::CCM::Path->new("/path/to/element");
my $property = EDG::WP4::CCM::Element->new($config, $path);
isa_ok($property, "EDG::WP4::CCM::Element",
       "property is an Element->new(config, Path)");

ok(!UNIVERSAL::isa($property, "EDG::WP4::CCM::Resource"),
   "property is not a Resource");

# validate inheritance of Element methods

# test getPath()
my $getpath = $property->getPath();
is($getpath->toString(), "/path/to/element", "property Element->getPath()");

# test getType()
is($property->getType(), EDG::WP4::CCM::Element->STRING, "property Element->getType() is STRING");

# test getDerivation()
my $derivation = $property->getDerivation();
is($derivation, "lxplus.tpl,hardware.tpl,lxplust_025.tpl",
   "property Element->getDerivation()");

# test getChecksum()
is($property->getChecksum(), md5_hex($derivation), "property Element->getChecksum()");

# test getDescription()
is($property->getDescription(), "an example of string", "property Element->getDescription()");

# test getValue()
ok($property->getValue(), "property Element->getValue()");

# test isType()
ok($property->isType(EDG::WP4::CCM::Element->STRING),
    "property Element->isType(STRING)");
ok(!$property->isType(EDG::WP4::CCM::Element->LONG),
    "!property Element->isType(LONG)");
ok(!$property->isType(EDG::WP4::CCM::Element->DOUBLE),
    "!property Element->isType(DOUBLE)");
ok(!$property->isType(EDG::WP4::CCM::Element->BOOLEAN),
    "!property Element->isType(BOOLEAN)");
ok(!$property->isType(EDG::WP4::CCM::Element->LIST),
    "!property Element->isType(LIST)");
ok(!$property->isType(EDG::WP4::CCM::Element->NLIST),
    "!property Element->isType(NLIST)");

# test isResource()
ok(!$property->isResource(), "!property Element->isResource()");

# test isProperty()
ok($property->isProperty(), "property Element->isProperty()");

done_testing();
