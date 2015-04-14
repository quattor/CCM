use strict;
use warnings;
use Test::More;
use Test::Quattor::TextRender::Component;

my $t = Test::Quattor::TextRender::Component->new(
    component => 'CCM',
    skippan => 1, # no pan files are shipped/exported
    )->test();

done_testing();
