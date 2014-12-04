#
# cache SyncFile.pm test script
# IMPORTANT: it does not test synchronisation issues
#
use strict;
use warnings;

use Test::More;
use myTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::SyncFile qw (read write);

use Cwd;
my $cdtmp = getcwd()."/target/tmp";
mkdir($cdtmp) if (! -d $cdtmp);

my $fn  = "$cdtmp/sf-test.txt";

my $tsy = "yes";
my $tsn = "no";

my $f = EDG::WP4::CCM::SyncFile->new($fn);

ok ($f, "EDG::WP4::CCM::SyncFile->new($fn)");
ok ($f->write ($tsy), "$f->write ($tsy)");
is ($f->read (), $tsy, "$f->write ()");
is ($f->get_file_name(), $fn, "$f->get_file_name()");

done_testing();
