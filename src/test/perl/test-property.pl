#!/usr/bin/perl -w

#
# test-property.pl	Test class Property
#
# $Id: test-property.pl,v 1.9 2006/06/26 13:44:58 gcancio Exp $
#
# Copyright (c) 2003 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

BEGIN {unshift(@INC,'/usr/lib/perl')};

use strict;
use POSIX qw (getpid);
use GDBM_File;
use Digest::MD5 qw(md5_hex);
use Test::Simple tests => 21;
use LC::Exception qw(SUCCESS throw_error);

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Element;
use EDG::WP4::CCM::Property;
use EDG::WP4::CCM::Path;

my $ec = LC::Exception::Context->new->will_store_errors;

# TODO: Use Test::More and t::Test

sub eok ($$$) {
  my ($cec, $result, $descr) = @_;
  unless ($result) {
    if ($cec->error) {
      ok (1, "exception: $descr");
      $cec->ignore_error();
      return SUCCESS;
    }
  }
  ok (0, "exception: $descr");
}

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

    tie(%hash, "GDBM_File", "${cache_dir}/${profile}/path2eid.db",
        GDBM_WRCREAT, 0644) or return();
    $key = "/path/to/element";
    $val = 0x00000001;
    $hash{$key} = pack("L", $val);
    untie(%hash);

    tie(%hash, "GDBM_File", "${cache_dir}/${profile}/eid2data.db",
        GDBM_WRCREAT, 0644) or return();
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

my ($property, $path, $string, $type);
my ($derivation, $checksum, $description, $value);

my ($cm, $config, $cache_dir, $profile, %hash, $key);

#
# Perform tests
#

$cache_dir = "/tmp/p_test";
$profile   = "profile.1";

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

$cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
$config = EDG::WP4::CCM::Configuration->new($cm, 1, 1);

# create property

$path = EDG::WP4::CCM::Path->new("/path/to/element");
$property = EDG::WP4::CCM::Property->new($config, $path);
ok(defined($property) && UNIVERSAL::isa($property,
                         "EDG::WP4::CCM::Property"),
                         "Property->new(config, Path)");

#
# validate inheritance of Element methods
#

# test getPath()
$path = $property->getPath();
$string = $path->toString();
ok($string eq "/path/to/element", "Property->getPath()");

# test getType()
$type = $property->getType();
ok($type == EDG::WP4::CCM::Property->STRING, "Property->getType()");

# test getDerivation()
$derivation = $property->getDerivation();
ok($derivation eq "lxplus.tpl,hardware.tpl,lxplust_025.tpl",
   "Property->getDerivation()");

# test getChecksum()
$checksum = $property->getChecksum();
ok($checksum eq md5_hex($derivation), "Property->getChecksum()");

# test getDescription()
$description = $property->getDescription();
ok($description eq "an example of string", "Property->getDescription()");

# test getValue()
$value = $property->getValue();
ok($value eq "a string", "Propety->getValue()");

# test isType()
ok($property->isType(EDG::WP4::CCM::Property->STRING),
    "Property->isType(STRING)");
ok(!$property->isType(EDG::WP4::CCM::Property->LONG),
    "!Property->isType(LONG)");
ok(!$property->isType(EDG::WP4::CCM::Property->DOUBLE),
    "!Property->isType(DOUBLE)");
ok(!$property->isType(EDG::WP4::CCM::Property->BOOLEAN),
    "!Property->isType(BOOLEAN)");
ok(!$property->isType(EDG::WP4::CCM::Property->LIST),
    "!Property->isType(LIST)");
ok(!$property->isType(EDG::WP4::CCM::Property->NLIST),
    "!Property->isType(NLIST)");

# test isResource()
ok(!$property->isResource(),   "!Property->isResource()");

# test isProperty()
ok($property->isProperty(),   "Property->isProperty()");

#
# test Property specific methods
#

# test getStringValue()
$value = $property->getStringValue();
ok( $value eq "a string", "Property->getStringValue()");

# test getDoubleValue()

eok($ec, $value = $property->getDoubleValue(),
    "EDG::WP4::CCM::Property->getDoubleValue()");

# test getLongValue()

eok($ec, $value = $property->getLongValue(),
    "EDG::WP4::CCM::Property->getLongValue()");

# test getBooleanValue()

eok($ec, $value = $property->getBooleanValue(),
    "EDG::WP4::CCM::Property->getBooleanValue()");

# test getStreamValue()

eok($ec, $value = $property->getBooleanValue(),
    "EDG::WP4::CCM::Property->getStreamValue()");

