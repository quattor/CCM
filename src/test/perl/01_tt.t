use strict;
use warnings;
use Test::More;
use Test::Quattor::ProfileCache qw(set_json_typed);
use Test::Quattor::TextRender::Component;
use EDG::WP4::CCM::Path qw(set_safe_unescape);

set_json_typed();

set_safe_unescape('/special/safe_unescape');
$EDG::WP4::CCM::Path::_safe_unescape_restore = ['/special/safe_unescape'];

my $t = Test::Quattor::TextRender::Component->new(
    component => 'CCM',
    skippan => 1, # no pan files are shipped/exported
    )->test();

done_testing();
