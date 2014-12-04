#
# Test EDG::WP4::CCM::DB
#

use strict;
use warnings;
use Test::More;
use Cwd;

use EDG::WP4::CCM::DB;

# require the default DB_File and current used
use DB_File;
use CDB_File;
use GDBM_File;

=pod

=HEAD1 DESCRIPTION

Test EDG::WP4::CCM::DB

=HEAD2 Generic tests

Test basic error handling

=cut

my $dbdtmp = getcwd()."/target/tmp";
my $dbd = "$dbdtmp/dbtest";
mkdir($dbdtmp) if (! -d $dbdtmp);
mkdir($dbd);
ok(-d $dbd, "DB dir $dbd exists.");

like(EDG::WP4::CCM::DB::test_supported_format("unsupported format"),
     qr{unsupported CCM database format 'unsupported format'},
    "test unsupported format returns error message");

like(EDG::WP4::CCM::DB::write({}, "$dbd/unsupported", "unsupported format"),
     qr{unsupported CCM database format 'unsupported format'},
    "write unsupported format returns error message");

open FH, ">$dbd/unsupported.fmt";
print FH "unsupported format\n";
close FH;

like(EDG::WP4::CCM::DB::read({}, "$dbd/unsupported"),
     qr{unsupported CCM database format 'unsupported format'},
    "read unsupported format returns error message");

# tries to open using default format DB_File
like(EDG::WP4::CCM::DB::read({}, "$dbd/doesnotexist"),
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

    my $pref="$dbd/".lc($name);
    my $err= EDG::WP4::CCM::DB::write($DATA, $pref, $fmt);
    
    ok(! defined($err), "No error while writing $name");
    ok(-f "$pref.db", "$name db file found");
    ok(-f "$pref.fmt", "$fmt fmt file found");

    my $data = {};
    $err= EDG::WP4::CCM::DB::read($data, $pref);
    ok(! defined($err), "No error while reading $name");

    is_deeply($data, $DATA, "Read correct data structure for $name");
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
