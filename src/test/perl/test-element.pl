#!/usr/bin/perl -w

#
# test-element.pl	Test class Element
#
# $Id: test-element.pl,v 1.13 2007/03/21 18:07:11 munoz Exp $
#
# Copyright (c) 2003 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

BEGIN {unshift(@INC,'/usr/lib/perl')};

use strict;
use POSIX qw (getpid);
use DB_File;
use Digest::MD5 qw(md5_hex);
use Test::More tests => 22;

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Element;
use EDG::WP4::CCM::Path;

#
# Generate an example of DBM file
#
sub gen_dbm ($$) {

    my ($cache_dir, $profile) = @_;
    my (%hash);
    my ($key, $val, $active);
    my ($derivation);

    # remove previous cache dir

    if ( $cache_dir eq "" ) {
        return ();
    }
    `rm -rf $cache_dir`;

    # create new profile

   `mkdir $cache_dir`;
   `mkdir $cache_dir/$profile`;
   `mkdir $cache_dir/$DATA_DN`;

   `echo 'no' > $cache_dir/$GLOBAL_LOCK_FN`;
   `echo '1' > $cache_dir/$CURRENT_CID_FN`;
   `echo '1' > $cache_dir/$LATEST_CID_FN`;

    $active = $profile . "/active." . getpid();
   `echo '1' > $cache_dir/$active`;

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

$cache_dir = "/tmp/e_test";
$profile   = "profile.1";

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

$cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
$config = EDG::WP4::CCM::Configuration->new($cm, 1, 1);

# create element with string path
$path = "/path/to/property";
$element = EDG::WP4::CCM::Element->new($config, $path);
ok(defined($element) && UNIVERSAL::isa($element, "EDG::WP4::CCM::Element"),
   "Element->new(config, string)");

# create element with Path object
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::Element->new($config, $path);
ok(defined($element) && UNIVERSAL::isa($element, "EDG::WP4::CCM::Element"),
   "Element->new(config, Path)");

# create resource with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/resource");
$element = EDG::WP4::CCM::Element->createElement($config, $path);
ok(defined($element) && UNIVERSAL::isa($element, "EDG::WP4::CCM::Resource"),
   "Element->createElement(config, Path_to_resource)");

# create property with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::Element->createElement($config, $path);
ok(defined($element) && UNIVERSAL::isa($element, "EDG::WP4::CCM::Property"),
   "Element->createElement(config, Path_to_property)");

# test getConfiguration()
$config = $element->getConfiguration();
$prof_dir  = $config->getConfigPath();
ok($prof_dir eq "$cache_dir/$profile", "Element->getConfiguration()");

# test getEID()
$eid = $element->getEID();
ok($eid == 1, "Element->getEID()");

# test getName()
$name = $element->getName();
ok($name eq "property", "Element->getName()");

# test getPath()
$path = $element->getPath();
$string = $path->toString();
ok($string eq "/path/to/property", "Element->getPath()");

# test getType()
$type = $element->getType();
ok($type == EDG::WP4::CCM::Element->STRING, "Element->getType()" );

# test getDerivation()
$derivation = $element->getDerivation();
ok($derivation eq "lxplus.tpl,hardware.tpl,lxplust_025.tpl",
   "Element->getDerivation()");

# test getChecksum()
$checksum = $element->getChecksum();
ok($checksum eq md5_hex($derivation), "Element->getChecksum()");

# test getDescription()
$description = $element->getDescription();
ok($description eq "an example of string", "Element->getDescription()");

# test getValue()
$value = $element->getValue();
ok($value eq "a string", "Element->getValue()");

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

# final clean-up
# `rm -rf $cache_dir`;


