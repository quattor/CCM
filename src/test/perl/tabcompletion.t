use strict;
use warnings;

use Test::More;
use CAF::Process;
use CAF::FileWriter;
use Readonly;
use File::Path qw(mkpath rmtree);

Readonly my $TAB_COMP => 'target/etc/quattor-ccm';
Readonly my $TAB_TESTDIR => 'target/test/tabcompletion';

rmtree($TAB_TESTDIR);
mkpath($TAB_TESTDIR);
my $fh = CAF::FileWriter->new("$TAB_TESTDIR/ccm.conf");
print $fh "cache_root $TAB_TESTDIR\n";
$fh->close();

# this is the order as listed by ls
my @cids = qw(1 10 100 11 110 111 112 2 3);
foreach my $cid (@cids) {
    mkpath("$TAB_TESTDIR/profile.$cid");
}
my $cidsreg = '^' . join(" ", @cids) . '$';

sub run_bash
{
    my ($regexp, $msg, $args, $echo_comp) = @_;

    my $p = CAF::Process->new(['bash', '-c']);

    my @bashargs = ("QUATTOR_CCM_CONF=$TAB_TESTDIR/ccm.conf", 'source', $TAB_COMP, '&&');
    push (@bashargs, @$args);

    push(@bashargs, '&&', 'echo', '${COMPREPLY[@]}') if $echo_comp;

    $p->pushargs(join(" ", @bashargs));

    my $output = $p->output();
    chomp($output);

    diag("Ran $p output $output.");
    like($output, $regexp, "$msg with $p");
}

sub test_func
{
    my ($regexp, $msg, @args) = @_;
    run_bash($regexp, $msg, \@args);
}

sub test_comp
{
    my ($regexp, $msg, @args) = @_;
    run_bash($regexp, $msg, \@args, 1);
}

test_func(qr{$cidsreg}, "Report all CIDs",
          '_quattor_ccm_get_cids');
test_func(qr{^1 10 100 11 110 111 112$}, "Report all CIDs starting with 1",
          '_quattor_ccm_get_cids', '1');
test_func(qr{^11 110 111 112$}, "Report all CIDs starting with 11",
          '_quattor_ccm_get_cids', '11');
test_func(qr{^112$}, "Report all CIDs starting with 112",
          '_quattor_ccm_get_cids', '112');

test_comp(qr{$cidsreg}, "Tabcomplete all CIDs",
          '_quattor_ccm_tabcomp_cids');
test_comp(qr{^11 110 111 112$}, "Tabcomplete all CIDs starting with 11",
          'COMP_WORDS=(11)', 'COMP_CWORD=0', '&&', '_quattor_ccm_tabcomp_cids');


done_testing();
