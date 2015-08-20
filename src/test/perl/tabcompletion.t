use strict;
use warnings;

use Test::More;
use CAF::Process;
use CAF::FileWriter;
use Readonly;
use File::Path qw(mkpath rmtree);
use Test::Quattor::ProfileCache;
use EDG::WP4::CCM::TextRender qw(ccm_format @CCM_FORMATS);
use Test::Quattor::TextRender::Base;

use EDG::WP4::CCM::CCfg qw(@CFG_KEYS);
use EDG::WP4::CCM::Options;
use EDG::WP4::CCM::CLI;

my $caf_trd = mock_textrender();

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

# create subtree with some files and directories to test compgen -f/-d
Readonly my $COMPGEN_BASE => "target/test/tabcompletion/compgen";
mkpath($COMPGEN_BASE);

my @compgen_dirs = qw(dir1 dir2);
my $compgen_dirs_full = [sort map {"$COMPGEN_BASE/$_"} @compgen_dirs];
foreach my $dir (@compgen_dirs) {
    mkpath("$COMPGEN_BASE/$dir");
}

my @compgen_files = qw(file1 file2);
foreach my $file (@compgen_files) {
    $fh = CAF::FileWriter->new("$COMPGEN_BASE/$file");
    print $fh "$file\n";
    $fh->close();
}
# add the dirs, they will also be considered for -f output
push(@compgen_files, @compgen_dirs);
my $compgen_files_full = [sort map {"$COMPGEN_BASE/$_"} @compgen_files];


sub run_bash
{
    my ($args, $echo_comp) = @_;

    my $p = CAF::Process->new(['bash', '-c']);

    my @bashargs = ("QUATTOR_CCM_CONF=$cfg->{cache_path}/ccm.conf", 'source', $TAB_COMP, '&&');
    push (@bashargs, @$args);

    push(@bashargs, '&&', 'echo', '${COMPREPLY[@]}') if $echo_comp;

    $p->pushargs(join(" ", @bashargs));

    my $output = $p->output();
    chomp($output);

    diag("Ran $p output $output.");
    return $output, "$p";
}

sub test_bash
{
    my ($test, $msg, $args, $echo_comp) = @_;

    my ($output, $cmdline) = run_bash($args, $echo_comp);

    if (ref($test) eq "ARRAY") {
        my @res = sort split(qr{\s+}, $output);
        is_deeply(\@res, $test, "$msg with $cmdline (test sorted results)");
    } else {
        like($output, $test, "$msg with $cmdline");
    }
}

sub test_func
{
    my ($test, $msg, @args) = @_;
    test_bash($test, $msg, \@args);
}

sub test_comp
{
    my ($test, $msg, @args) = @_;
    test_bash($test, $msg, \@args, 1);
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
          'COMP_WORDS=(SCRIPTNAME 11)', 'COMP_CWORD=1', '&&', '_quattor_ccm_tabcomp_cids');

# Test current CID
my $cidreg = '^'.$cfg->{cid}.'$';
test_func(qr{$cidreg}, "Report current CID", '_quattor_ccm_get_current_cid');
test_func(qr{$cidreg}, "Report latest CID", '_quattor_ccm_get_latest_cid');

# Test pan
my $compres_pan_path_system_network = [sort qw(/system/network/default_gateway /system/network/domainname /system/network/hostname /system/network/interfaces/ /system/network/nameserver/ /system/network/nozeroconf /system/network/set_hwaddr)];
test_func(qr{^/system/$}, "Report pan path ''",
          '_quattor_ccm_pan_path', $cfg->{cid});
test_func(qr{^/system/network/$}, "Report pan path '/system/'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/');
test_func(qr{^/system/network/$}, "Report pan path '/system/n'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/n');
test_func(qr{^/system/network/$}, "Report pan path '/system/network'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network');
test_func($compres_pan_path_system_network,
          "Report pan path '/system/network/'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/');
test_func(qr{^/system/network/default_gateway$},
          "Report pan path '/system/network/def'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/def');
test_func(qr{^$}, # at least one new character required in path, otherwise assume scalar
          "Report pan path '/system/network/default_gateway'",
          '_quattor_ccm_pan_path', $cfg->{cid}, '/system/network/default_gateway');

# use current CID by default
test_comp($compres_pan_path_system_network,
          "Tabcomplete '' (tries max-depth)",
          '_quattor_ccm_tabcomp_pan_path');
test_comp($compres_pan_path_system_network,
          "Tabcomplete '/sy'",
          'COMP_WORDS=(SCRIPTNAME /sy)', 'COMP_CWORD=1', '&&', '_quattor_ccm_tabcomp_pan_path');
test_comp(qr{^/system/network/default_gateway$},
          "Tabcomplete '/system/network/def'",
          'COMP_WORDS=(SCRIPTNAME /system/network/def)', 'COMP_CWORD=1', '&&', '_quattor_ccm_tabcomp_pan_path');
test_comp(qr{^$}, # one match, found the scalar
          "Tabcomplete '/system/network/default_gateway'",
          'COMP_WORDS=(SCRIPTNAME /system/network/default_gateway)', 'COMP_CWORD=1', '&&', '_quattor_ccm_tabcomp_pan_path');

test_comp(qr{^/system/nothing$},
          "Tabcomplete '/sys' with CID 1",
          '_quattor_ccm_tabcomp_active_cid=1', 'COMP_WORDS=(SCRIPTNAME /sys)', 'COMP_CWORD=1', '&&', '_quattor_ccm_tabcomp_pan_path');

# Test options tabcompletions lists
sub bash_split_opts
{
    my ($varname) = @_;
    my ($output, $cmdline) = run_bash(['echo', '${'.$varname.'[@]}']);
    my @opts = sort split(qr{\s+}, $output);
    return \@opts;
}

# CFG_KEYS is sorted
is_deeply(bash_split_opts('_quattor_ccm_CCfg_options'),
          \@CFG_KEYS,
          "_quattor_ccm_CCfg_options");
my $CCfg_longopts = [map {"--$_"} @CFG_KEYS];
is_deeply(bash_split_opts('_quattor_ccm_CCfg_longoptions'),
          $CCfg_longopts,
          "_quattor_ccm_CCfg_longoptions");

# CLI formats
is_deeply(bash_split_opts('_quattor_ccm_CLI_formats'),
          \@CCM_FORMATS, # is already sorted
          "_quattor_ccm_CLI_formats");

sub NAME_to_opt
{
    # each arg is a NAME element, eg name|alias|<singlelettershorthand>=something
    my @res;
    foreach my $option (@_) {
        my $nametxt = [split("=", $option->{NAME})]->[0];
        my @names = split(qr{\|}, $nametxt);
        # remove single letter option
        push(@res, grep {length($_) != 1} @names);
    };
    return @res;
}

# not sure how to test the individual non-long _options
my $inst = EDG::WP4::CCM::Options->new("test", '--cfgfile', 'src/test/resources/ccm.cfg');
my $Options_longopts = [sort map {"--$_"} NAME_to_opt(@{$inst->app_options()})];
is_deeply([sort @{bash_split_opts('_quattor_ccm_Options_longoptions')}],
          $Options_longopts,
          "_quattor_ccm_Options_longoptions");

$inst = EDG::WP4::CCM::CLI->new("test", '--cfgfile', 'src/test/resources/ccm.cfg');
my $CLI_longopts = [sort map {"--$_"} NAME_to_opt(@{$inst->app_options()})];
is_deeply([sort @{bash_split_opts('_quattor_ccm_CLI_longoptions')}],
          $CLI_longopts,
          "_quattor_ccm_CLI_longoptions");

# test handle functions
#   pass option, should return 0;
#   pass other option, should return 1

# for bash function func and args, test if bash exitcode is ec
sub test_handle
{
    my($handle, $ec, $longopt) = @_;
    my $func = "_quattor_ccm_${handle}_handle_options";
    # this tests prev, which is COMP_WORDS[COMP_CWORD-1]
    my ($output, $cmdline) = run_bash(["COMP_WORDS=(SCRIPTNAME $longopt)", 'COMP_CWORD=2', '&&', $func]);
    diag("test_handle $cmdline returned $output with (perl) ec $?");
    is($? >> 8, $ec, "Tested handle $func with ec $ec and longopt $longopt");
}

foreach my $longopt (@$CCfg_longopts) {
    test_handle('CCfg', 0, $longopt);
}
test_handle('CCfg', 1, 'not_a_real_longopt');


foreach my $longopt (@$Options_longopts) {
    # remove all CCfg options, they are not handled
    next if grep {$_ eq $longopt} @$CCfg_longopts;
    test_handle('Options', 0, $longopt);
}
test_handle('Options', 1, 'not_a_real_longopt');

foreach my $longopt (@$CLI_longopts) {
    # remove all CCfg and Options options, they are not handled
    next if grep {$_ eq $longopt} @$CCfg_longopts;
    next if grep {$_ eq $longopt} @$Options_longopts;
    test_handle('CLI', 0, $longopt);
}
test_handle('CLI', 1, 'not_a_real_longopt');

# test options
sub test_comp_handle_longopt
{
    my($handle, $longopt, $val, $test) = @_;
    my $func = "_quattor_ccm_${handle}_handle_options";
    test_comp($test,
              "Tabcomplete $longopt (val $val) for fn $func",
              "COMP_WORDS=(SCRIPTNAME --$longopt $val)", 'COMP_CWORD=2', '&&', $func);
}

#
# CCfg
#
# is a compgen -d
foreach my $opt (qw(cache_root ca_dir)) {
    test_comp_handle_longopt("CCfg", $opt, "$COMPGEN_BASE/", $compgen_dirs_full);
}
# is a compgen -f
foreach my $opt (qw(ca_file cert_file key_file)) {
    test_comp_handle_longopt("CCfg", $opt, "$COMPGEN_BASE/", $compgen_files_full);
}



#
# Options
#
# is a compgen -f
foreach my $opt (qw(cfgfile)) {
    test_comp_handle_longopt("Options", $opt, "$COMPGEN_BASE/", $compgen_files_full);
}

# mainly tests _quattor_ccm_tabcomp_cids
test_comp_handle_longopt("Options", "cid", "", [sort @cids]);

# mainly tests _quattor_ccm_tabcomp_pan_path
test_comp_handle_longopt("Options", "profpath", "/system/network/", $compres_pan_path_system_network);

#
# CLI
#
# mainly tests variabele $_quattor_ccm_CLI_formats
test_comp_handle_longopt("CLI", "format", "", \@CCM_FORMATS);

# _quattor_ccm_CLI
# unsupported option / empty option prints all options
#   this tests the pass through
test_comp($CLI_longopts,
          "tabcomplete _quattor_ccm_CLI",
          'COMP_WORDS=(SCRIPTNAME)', 'COMP_CWORD=1', '&&', '_quattor_ccm_CLI');
test_comp(\@CCM_FORMATS, "Tabcomplete formats with _quattor_ccm_CLI",
          'COMP_WORDS=(SCRIPTNAME --format)', 'COMP_CWORD=2', '&&', '_quattor_ccm_CLI');

# test ccm binding
test_bash(qr{^complete -F _quattor_ccm_CLI ccm$}m,
          "tabcompletion frunction _quattor_ccm_CLI for ccm command",
          ["complete", "-p"]);

done_testing();
