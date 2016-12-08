use strict;
use warnings;
use Test::More;

use LC::Exception;
use EDG::WP4::CCM::Fetch::Config qw(NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

is(NOQUATTOR, "/etc/noquattor", "Exported NOQUATTOR");
is(NOQUATTOR_EXITCODE, "3", "Exported NOQUATTOR_EXITCODE");
is(NOQUATTOR_FORCE, "force-quattor", "Exported NOQUATTOR_FORCE");

my $ec = LC::Exception::Context->new->will_store_errors;
# Use a plain hash as fake instance
# This is ok to test the exception throwing
my $inst = {};

my $prp = 'service/test-server.domain@realm.something';
ok(EDG::WP4::CCM::Fetch::Config::setPrincipal($inst, $prp),
   "setPrincipal ok");
is($inst->{PRINCIPAL}, $prp, "setPrincipal sets PRINCIPAL attribute");
ok(! $ec->error, "No error thrown by valid principal");

# This tests that the backslash is not a valid char in the regexp,
# and the the . is a ., not just any char
EDG::WP4::CCM::Fetch::Config::setPrincipal($inst, 'random/garbage\with@backslash');
ok($ec->error, "Error thrown by invalid principal");
like($ec->error->text, qr{}, "expected exception message thrown by invalid principal");
$ec->ignore_error;

done_testing;
