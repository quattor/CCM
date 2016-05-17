use strict;
use warnings;

use Test::More;

# Old API, actual code in Path
use EDG::WP4::CCM::Element qw(escape unescape);

=pod

=head1 DESCRIPTION

Test the escaping and unescaping functionalities.

=cut

is(unescape(escape("kernel-2.6.32")), "kernel-2.6.32",
   "Escaping and unescaping cancel each other out");

is(escape("kernel-2.6.32"), "kernel_2d2_2e6_2e32",
   "Escaping works as expected");
is(unescape("kernel_2d2_2e6_2e32"), "kernel-2.6.32",
   "Unescaping works as expected");

done_testing();
