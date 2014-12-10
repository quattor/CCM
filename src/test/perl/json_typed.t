#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;

use Test::More tests => 11;
use EDG::WP4::CCM::XMLPanProfile;
use EDG::WP4::CCM::JSONProfileTyped;
use EDG::WP4::CCM::Fetch;
use CAF::FileReader;
use JSON::XS qw(decode_json);
use Test::Deep;
use XML::Parser;
use EDG::WP4::CCM::Fetch qw(ComputeChecksum);
use File::Path qw(make_path);
use B;

use Readonly;

=pod

=head1 SYNOPSIS

Tests for the JSON typed interpreter.

The module and output are different from the JSONProfileSImple interpreter, 
as the JSONProfileSimple does not support all scalar types.
The output should be equal to the XMLPanProfile interpreter.

=cut

=pod

Test JSON::XS behaviour w.r.t. keeping data type close to XS-type after decode.
(Otherwise the re-encode would not retrun the original string or data).

=cut 

# Test data hash
Readonly::Hash my %DATA => {
    a => 'a',
    b => 0.5,
    c => 1,
    d => -2,
};

# Ordered JSON encoding of %DATA
Readonly my $DATA_STRING => '{"a":"a","b":0.5,"c":1,"d":-2}';

# Expected types
Readonly::Hash my %TYPES => {
    a => 'string',
    b => 'double',
    c => 'long',
    d => 'long',
};

# make json string, canonical sorts the keys
my $jxs = JSON::XS->new();
$jxs->canonical(1);
ok($jxs->get_canonical, "JSON::XS canoncial enabled for sorted keys encoding");

my $copy1 = {};
foreach my $k (keys %DATA) {
    $copy1->{$k} = $DATA{$k};
}

# canonical encoding of Readonly seems troublesome. Use copy.
my $jsonstring1 = $jxs->encode($copy1);
my $json = $jxs->decode($jsonstring1);

# BTYPES mapping gtest with json decoded instance
foreach my $k (keys %$json) {
    is(EDG::WP4::CCM::JSONProfileTyped::get_scalar_type(B::svref_2object(\$json->{$k})), 
        $TYPES{$k}, 
        "get_scalar_type mapping key $k");
}

my $copy2 = {};
foreach my $k (keys %$json) {
    $copy2->{$k} = $json->{$k};
}

my $jsonstring2 = $jxs->encode($copy2);

is_deeply($copy1, \%DATA, "copy of DATA is original DATA");
is_deeply($json, \%DATA, "decode(encode) returns original DATA");
is_deeply($copy2, \%DATA, "copy of decode(encode) is original DATA");
is($jsonstring1, $DATA_STRING, "Encoding of DATA returns expected string");
is($jsonstring2, $DATA_STRING, "Encoding of original and copy is expected string");



sub compile_profile
{
    my ($type, $simple) = @_;
    make_path('target/test/json');
    system("cd src/test/resources && panc --formats $type --output-dir ../../../target/test/json ${simple}profile.pan");
}



=pod

The test is trivial: just grab a Pan-formatted XML, parse it and
interpret it with the previous and with the current interpreters. They
must be identical.

=cut

my $simple = ''; # set to 'simple' for old 'all scalar are string' behaviour

compile_profile("pan", $simple);
compile_profile("json", $simple);

my $fh = CAF::FileReader->new("target/test/json/${simple}profile.xml");
my $t = XML::Parser->new(Style => 'Tree')->parse("$fh");
my $reference_result = EDG::WP4::CCM::XMLPanProfile->interpret_node(@$t);

$fh = CAF::FileReader->new("target/test/json/${simple}profile.json");
note("Profile contents: $fh");
$t = decode_json("$fh");
my $our_result = EDG::WP4::CCM::JSONProfileTyped->interpret_node(profile => $t);

# Do not explain before creating result. It might do some auto-stringification
note("Tree=", explain($t));

cmp_deeply($our_result, $reference_result, "Our result matches the xml implementation");
note("Reference=", explain($reference_result));
note("Our=", explain($our_result));

done_testing();
