use strict;
use warnings;


use Test::More;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use EDG::WP4::CCM::CLI;
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN);
use EDG::WP4::CCM::Path qw(escape);
use Test::MockModule;
use Test::Quattor::TextRender::Base;

my $caf_trd = mock_textrender();

my $optmock = Test::MockModule->new('EDG::WP4::CCM::Options');
my @print;
# use [@_] to append a copy, not a reference to the (last) args in recent perl
$optmock->mock('_print', sub {shift; push(@print, [@_]);});

# Actually test a CCM app instance using existing CCM
# Cannot use Test::Quattor import due to CAF mocking
my $ppc_cfg = prepare_profile_cache('cli');

my $apppath = "target/sbin/ccm";
my @baseopts = (
    $apppath,
    '--cfgfile', 'src/test/resources/ccm.cfg',
    '--cache_root', $ppc_cfg->{cache_path},
    );

my $cli = EDG::WP4::CCM::CLI->new(@baseopts);
my @allopts = map {$_->{NAME}} @{$cli->app_options()};

# number of new options compared to CCM::Options
my $newopts = 1;
is_deeply([@allopts[-$newopts .. -1]],
          ['format=s'],
          "Added CLI options as expected");

my @actions = sort keys %{$cli->add_actions()};
is_deeply(\@actions,
          [qw(dumpdb show showcids )],
          "expected CLI actions");

# show with default format
@print = ();
my $cli_show = EDG::WP4::CCM::CLI->new(@baseopts,
    '--profpath', '/a',
    '--show',
    );
isa_ok($cli_show, "EDG::WP4::CCM::CLI", "cli_show is a EDG::WP4::CCM::CLI instance");
is_deeply($cli_show->{profpaths}, [], 'Empty arrayref with no non-option commandline options as profpaths');
is_deeply($cli_show->gatherPaths(@{$cli_show->{profpaths}}), ['/a'], 'Expected selected paths');

ok($cli_show->action(), "action with show and default format returns success");
is_deeply(\@print, [["\$ a : 'b'\n"],], "show with default format gives correct result");

# default options, non-option args
@print = ();
$cli_show = EDG::WP4::CCM::CLI->new(@baseopts, '/a');
isa_ok($cli_show, "EDG::WP4::CCM::CLI", "cli_show is a EDG::WP4::CCM::CLI instance (default action/format and non-opt args)");
is_deeply($cli_show->{profpaths}, ['/a'], 'non-option commandline options as profpaths');
is_deeply($cli_show->gatherPaths(@{$cli_show->{profpaths}}), ['/a'], 'Expected selected paths with non-opt args');

ok($cli_show->action(), "default action/format and non-opt args returns success");
is_deeply(\@print, [["\$ a : 'b'\n"],], "default action/format and non-opt args gives correct result");


# dumpdb action
@print = ();
my $cli_dumpdb = EDG::WP4::CCM::CLI->new(@baseopts,
    '--dumpdb',
    );
isa_ok($cli_dumpdb, "EDG::WP4::CCM::CLI", "cli_dumpdb is a EDG::WP4::CCM::CLI instance");
ok($cli_dumpdb->action(), "action with dumpdb returns success");
my $txt = join('', map {join('',@$_)} @print);
like($txt,
     qr{path2eid:\n/ => 0\n/a => 1\n},
     "dumpdb output path2eid");
# \0 separated list of subpaths
like($txt,
     qr{eid2data:\n0 => a\0c\0e\n10000000 => nlist\n20000000 => 1740877ebcb53b5132e75cff986cd705\n1 => b}m,
     "dumpdb output eid2data");
like($txt,
     qr{path2eid and eid2data combined:\n/ \(0\) =>\n  V: a\0c\0e\n  T: nlist\n  C: 1740877ebcb53b5132e75cff986cd705\n  D: <undef>\n/a \(1\) =>\n},
     "dumpdb ouptut combined path2eid eid2data");
diag $txt;


done_testing();

1;
