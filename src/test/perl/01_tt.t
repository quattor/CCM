use strict;
use warnings;
use Test::More;
use Test::Quattor::ProfileCache qw(set_json_typed);
use Test::Quattor::TextRender::Component;

set_json_typed();

my $t = Test::Quattor::TextRender::Component->new(
    component => 'CCM',
    skippan => 1, # no pan files are shipped/exported
    )->test();

done_testing();
