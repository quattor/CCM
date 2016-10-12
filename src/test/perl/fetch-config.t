use strict;
use warnings;
use Test::More;

use EDG::WP4::CCM::Fetch::Config qw(NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

is(NOQUATTOR, "/etc/noquattor", "Exported NOQUATTOR");
is(NOQUATTOR_EXITCODE, "3", "Exported NOQUATTOR_EXITCODE");
is(NOQUATTOR_FORCE, "force-quattor", "Exported NOQUATTOR_FORCE");

done_testing;
