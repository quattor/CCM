use strict;
use warnings;

use Test::More;

use EDG::WP4::CCM::CacheManager::Encode qw(
    UNDEFINED ELEMENT PROPERTY RESOURCE STRING
    LONG DOUBLE BOOLEAN LIST NLIST LINK TABLE RECORD
    type_from_name decode_eid encode_eids
    $PATH2EID $EID2DATA @EIDS_PACK
);

is($PATH2EID, 'path2eid', 'path2eid DB filename');
is($EID2DATA, 'eid2data', 'eid2data DB filename');

my %map = %EDG::WP4::CCM::CacheManager::Encode::NAME_TYPE_MAP;

is_deeply(\%map, {
    string => STRING,
    double => DOUBLE,
    long => LONG,
    boolean => BOOLEAN,
    list => LIST,
    nlist => NLIST,
    link => LINK,
    table => TABLE,
    record => RECORD,
}, "mapping from type name to type constant");

foreach my $name (sort keys %map) {
    is(type_from_name($name), $map{$name}, "type_from_name with name $name");
};

is(type_from_name('something'), UNDEFINED, "type_from_name returns UNDEFINED");

is_deeply(\@EIDS_PACK,
          [qw(VALUE TYPE DERIVATION CHECKSUM DESCRIPTION)],
          "EIDS_PACK array");

is_deeply(encode_eids(123), {
    VALUE => pack('L', 123),
    TYPE => pack('L', 1 << 28 | 123),
    DERIVATION => pack('L', 2 << 28 | 123),
    CHECKSUM => pack('L', 3 << 28 | 123),
    DESCRIPTION => pack('L', 4 << 28 | 123),
}, "encode_eids for id 123");

is(decode_eid(encode_eids(123)->{VALUE}), 123, "decode encoded eid returns original");


done_testing;
