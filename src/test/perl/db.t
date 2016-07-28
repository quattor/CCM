#
# Test EDG::WP4::CCM::DB
#

use strict;
use warnings;
use Test::More;
use Cwd;

use Test::Quattor::Object;
use EDG::WP4::CCM::DB qw(read_db);

# require the default DB_File and current used
use DB_File;
use CDB_File;
use GDBM_File;

is($EDG::WP4::CCM::DB::DEFAULT_FORMAT, 'DB_File', "DB_File is default format");
is_deeply([sort keys %EDG::WP4::CCM::DB::FORMAT_DISPATCH],
          [qw(CDB_File DB_File GDBM_File)],
          "Supported formats");

=pod

=HEAD1 DESCRIPTION

Test EDG::WP4::CCM::DB

=HEAD2 Generic tests

Test basic error handling

=cut

my $obj = Test::Quattor::Object->new();

my $dbdtmp = getcwd()."/target/tmp";
my $dbd = "$dbdtmp/dbtest";

mkdir($dbdtmp) if (! -d $dbdtmp);
mkdir($dbd);
ok(-d $dbd, "DB dir $dbd exists.");

my $prefix = "$dbd/init_test";
my $db = EDG::WP4::CCM::DB->new($prefix, log => $obj);

isa_ok($db, 'EDG::WP4::CCM::DB', 'new returns a EDG::WP4::CCM::DB instance');
is($db->{prefix}, $prefix, "prefix attribute is set");

ok(! defined($db->test_supported_format("unsupported format 1")),
     "test unsupported format 1 returns undef");
like($db->{fail},
     qr{unsupported CCM database format 'unsupported format 1'},
     "test unsupported format 1 sets fail attribute");

like($db->write({}, "unsupported format 2"),
     qr{unsupported CCM database format 'unsupported format 2'},
    "write unsupported format 2 returns error message");

open FH, ">$dbd/unsupported.fmt";
print FH "unsupported format 3\n";
close FH;

like(read_db({}, "$dbd/unsupported"),
     qr{unsupported CCM database format 'unsupported format 3'},
    "read unsupported format 3 returns error message");

# tries to open using default format DB_File
like(read_db({}, "$dbd/doesnotexist"),
     qr{failed to open DB_File},
    "read non existing file returns error message");

sub test_fmt {
    my $fmt = shift;

    my $name = $fmt;
    $name = 'DEFAULT' if (! defined($name));

    my $DATA = {
        a => 1,
        b => 2,
        c => 3,
    };

    my $pref = "$dbd/".lc($name);
    my $db = EDG::WP4::CCM::DB->new($pref, log => $obj);
    my $err= $db->write($DATA, $fmt, {mode => 0604}); # very non-standard mode

    ok(! defined($err), "No error while writing $name");
    ok(-f "$pref.db", "$name db file found");
    is((stat("$pref.db"))[2] & 07777, 0604, "mode set via status on db file");
    ok(-f "$pref.fmt", "$fmt fmt file found");
    is((stat("$pref.fmt"))[2] & 07777, 0604, "mode set via filewriter on format file");

    my $data = {};
    $err = read_db($data, $pref);
    ok(! defined($err), "No error while reading $name");
    is_deeply($data, $DATA, "Read correct data structure for $name");

    # Test legacy read
    my $datal = {};
    $err = EDG::WP4::CCM::DB::read($datal, $pref);
    ok(! defined($err), "No error while reading $name legacy read");
    is_deeply($datal, $DATA, "Read correct data structure for $name legacy read");
}

=pod

=HEAD2 DB_File

Test DB_File

=cut

test_fmt("DB_File");


=pod

=HEAD2 CDB_File

Test CDB_File

=cut

test_fmt("CDB_File");

=pod

=HEAD2 GDBM_File

Test GDBM_File

=cut

test_fmt("GDBM_File");


done_testing();
