use strict;
use warnings;

use Test::More;
use CAF::Process;
use CAF::FileWriter;
use Readonly;
use File::Path qw(mkpath rmtree);
use Test::Quattor::ProfileCache;
use EDG::WP4::CCM::TextRender qw(ccm_format);
use Test::Quattor::TextRender::Base;

my $caf_trd = mock();

Readonly my $TAB_COMP => 'target/etc/quattor-ccm';

my $cfg = prepare_profile_cache('tabcompletion');

my $fh = CAF::FileWriter->new("$cfg->{cache_path}/ccm.conf");
print $fh "cache_root $cfg->{cache_path}\n";
$fh->close();

my $el = $cfg->getElement('/');
my $fmt = ccm_format('tabcompletion', $el);
diag("$fmt");

$fh = CAF::FileWriter->new("$cfg->{cfg_path}/tabcompletion");
print $fh "$fmt";
$fh->close();

# this is the order as listed by ls
my @cids = qw(1 10 100 11 110 111 112 2 3);
foreach my $cid (@cids) {
    mkpath("$cfg->{cache_path}/profile.$cid");
}
my $cidsreg = '^' . join(" ", @cids) . '$';

$fh = CAF::FileWriter->new("$cfg->{cache_path}/profile.1/tabcompletion");
print $fh "/\n/system/\n/system/nothing\n";
$fh->close();


sub run_bash
{
    my ($regexp, $msg, $args, $echo_comp) = @_;

    my $p = CAF::Process->new(['bash', '-c']);

    my @bashargs = ("QUATTOR_CCM_CONF=$cfg->{cache_path}/ccm.conf", 'source', $TAB_COMP, '&&');
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

# Test get CIDs

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

# Test current CID
my $cidreg = '^'.$cfg->{cid}.'$';
test_func(qr{$cidreg}, "Report current CID", '_quattor_ccm_get_current_cid');
test_func(qr{$cidreg}, "Report latest CID", '_quattor_ccm_get_latest_cid');

# Test pan
test_func(qr{^/system/$}, "Report pan path ''",
          '_quattor_ccm_pan_path', $cfg->{cid});
test_func(qr{^/system/network/$}, "Report pan path '/system/'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/');
test_func(qr{^/system/network/$}, "Report pan path '/system/n'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/n');
test_func(qr{^/system/network/$}, "Report pan path '/system/network'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network');
test_func(qr{^/system/network/default_gateway /system/network/domainname /system/network/hostname /system/network/interfaces/ /system/network/nameserver/ /system/network/nozeroconf /system/network/set_hwaddr$},
          "Report pan path '/system/network/'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/');
test_func(qr{^/system/network/default_gateway$},
          "Report pan path '/system/network/def'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/def');
test_func(qr{^$}, # at least one new character required in path, otherwise assume scalar
          "Report pan path '/system/network/default_gateway'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/default_gateway');

# use current CID by default
test_comp(qr{^/system/network/default_gateway /system/network/domainname /system/network/hostname /system/network/interfaces/ /system/network/nameserver/ /system/network/nozeroconf /system/network/set_hwaddr$},
          "Tabcomplete '' (tries max-depth)",
          '_quattor_ccm_tabcomp_pan_path');
test_comp(qr{^/system/network/default_gateway /system/network/domainname /system/network/hostname /system/network/interfaces/ /system/network/nameserver/ /system/network/nozeroconf /system/network/set_hwaddr$},
          "Tabcomplete '/sy'",
          'COMP_WORDS=(/sy)', 'COMP_CWORD=0', '&&', '_quattor_ccm_tabcomp_pan_path');
test_comp(qr{^/system/network/default_gateway$},
          "Tabcomplete '/system/network/def'",
          'COMP_WORDS=(/system/network/def)', 'COMP_CWORD=0', '&&', '_quattor_ccm_tabcomp_pan_path');
test_comp(qr{^$}, # one match, found the scalar
          "Tabcomplete '/system/network/default_gateway'",
          'COMP_WORDS=(/system/network/default_gateway)', 'COMP_CWORD=0', '&&', '_quattor_ccm_tabcomp_pan_path');

test_comp(qr{^/system/nothing$},
          "Tabcomplete '/sys' with CID 1",
          '_quattor_ccm_tabcomp_active_cid=1', 'COMP_WORDS=(/sys)', 'COMP_CWORD=0', '&&', '_quattor_ccm_tabcomp_pan_path');


done_testing();
