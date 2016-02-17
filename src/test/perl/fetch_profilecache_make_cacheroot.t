#!/usr/bin/perl


=pod

=head1 SYNOPSIS

Script that tests the EDG::WP4::CCM::Fetch::profielCache MakeCacheRoot function

(separate due to complicated mocking of builtins

=head1 TEST ORGANIZATION

=cut

use strict;
use warnings;
use Test::More;
# to be able to mock them with MockModule
# order of use is important (fake sub namespace before the ProfileCache (and Fetch) loads it)
use subs qw(
    EDG::WP4::CCM::Fetch::ProfileCache::mkdir
    EDG::WP4::CCM::Fetch::ProfileCache::chown
    EDG::WP4::CCM::Fetch::ProfileCache::chmod
    EDG::WP4::CCM::Fetch::ProfileCache::umask
    EDG::WP4::CCM::Fetch::ProfileCache::getgrnam
);
use EDG::WP4::CCM::Fetch::ProfileCache qw(MakeCacheRoot);

use Test::Quattor::Object;

use Test::MockModule;

=pod

=head2 Test MakeCacheRoot

Test the creation of cache root

=cut

my $mock_profcache = Test::MockModule->new('EDG::WP4::CCM::Fetch::ProfileCache');

# directory should not be used, all calls are mocked
my $cr = "target/test/make_cache_root";

my $calls = {};

foreach my $m (qw(chmod chown mkdir umask getgrnam)) {
  $calls->{$m} = [];
  # return 20 (is not 0, and used as gid)
  $mock_profcache->mock($m, sub { push(@{$calls->{$m}}, \@_); 20; });
};

my $dirs = { "$cr/tmp" => 1 };
$mock_profcache->mock('_directory_exists', sub { my $dir = shift; return $dirs->{$dir}; });

my $obj = Test::Quattor::Object->new();

MakeCacheRoot($cr, 'mygroup', 1, $obj, "profile.3");

is_deeply($calls->{mkdir}, [[$cr, 0755], ["$cr/data", 0755], ["$cr/profile.3", 0755]],
          "mkdir called as expected (only on non-existing dirs)");
is_deeply($calls->{chmod}, [[0755, "$cr/tmp"]],
          "chmod called as expected (only on existing dir)");
is_deeply($calls->{chown}, [[$>, 20, $cr], [$>, 20, "$cr/data"], [$>, 20, "$cr/tmp"], [$>, 20, "$cr/profile.3"]],
          "chown called as expected");
is_deeply($calls->{umask}, [], "umask not called (world_readable is set)");
is_deeply($calls->{getgrnam}, [['mygroup']], "getgrnam called");


done_testing;
