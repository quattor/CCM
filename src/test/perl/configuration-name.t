use strict;
use warnings;

use Test::More;
use Test::Quattor::ProfileCache;
use Test::Quattor::TextRender::Base;

use EDG::WP4::CCM::CacheManager::Configuration;
use Cwd qw(getcwd);

my $caf_trd = mock_textrender();

my $cfg = prepare_profile_cache('names');
my $cfg_no_metadata = prepare_profile_cache('names_no_metadata');

=head1 Constants

=cut

is($EDG::WP4::CCM::CacheManager::Configuration::DEFAULT_NAME_TEMPLATE_TYPE, 'name',
   'Default name template type is name');
is_deeply(\@EDG::WP4::CCM::CacheManager::Configuration::NAME_TEMPLATE_TYPES,
          [qw(name)],
          'Allowed name template types');

=head1 Verify names TT

Test that each shipped name template has all required type TT files

=cut

my $ttdir = getcwd().'/target/share/templates/quattor/CCM/names/';
foreach my $name_template (glob("$ttdir/*")) {
    foreach my $type (@EDG::WP4::CCM::CacheManager::Configuration::NAME_TEMPLATE_TYPES) {
        my $ttfn = "$name_template/$type.tt";
        ok(-f $ttfn, "Found TT $ttfn for name template $name_template type $type");
    }
}

=head1 getName

=cut

# We can assume all TT files are unittested

# first arg is unused cred
# default name basic is set via CCfg, so force undef
my $cfg1 = $cfg->{cache_manager}->getConfiguration(undef, $cfg->{cid}, name_template => undef);
# no name attr set
ok(! defined($cfg1->{name}), "No name template passed, no name attribute set");
$cfg1->{fail} = undef;
ok(! defined($cfg1->getName()), "getName returns undef with no name template set");
ok(! defined($cfg1->{fail}), "getName does not set fail attr with no name template set");

my $cfg2 = $cfg->{cache_manager}->getConfiguration(undef, $cfg->{cid}, name_template => 'does_not_exist');
is_deeply($cfg2->{name}, {template => 'does_not_exist'},
          "name template does_not_exist passed, name attribute set");
$cfg2->{fail} = undef;
ok(! defined($cfg2->getName()), "getName returns undef with non-existing template set");
like($cfg2->{fail},
     qr{^Failed to getName: Failed to render with module names/does_not_exist/name.tt: Non-existing template names},
     "getName set fail attr with non-existing name template set");

# Test renderfailure?
$caf_trd->mock('tt', sub {my $self = shift; return $self->fail("mocked failure");});
my $cfg3 = $cfg->{cache_manager}->getConfiguration(undef, $cfg->{cid}, name_template => 'basic');
$cfg3->{fail} = undef;
ok(! defined($cfg3->getName()), "getName returns undef in case of render failure");
is($cfg3->{fail},
   'Failed to getName: Failed to render with module names/basic/name.tt: mocked failure',
   "getName set fail attr with render failure");

# Restore original behaviour
$caf_trd->unmock('tt');

# Test success
my $cfg4 = $cfg->{cache_manager}->getConfiguration(undef, $cfg->{cid}, name_template => 'basic');
is_deeply($cfg4->{name}, {template => 'basic'},
          "name template basic passed, name attribute set");
$cfg4->{fail} = undef;
is($cfg4->getName(), "mybranch-sandbox-user123-3b91b01-1476014841", "correct name with template name basic");
ok(! defined($cfg4->{fail}), "getName does not set fail attr with correct rendered name");

# unknown type
my $cfg5 = $cfg->{cache_manager}->getConfiguration(undef, $cfg->{cid}, name => 'basic');
$cfg5->{fail} = undef;
ok(! defined($cfg5->getName('unsupported_type')), "getName returns undef with unsupported type");
is($cfg5->{fail}, 'Invalid name template type unsupported_type', "getName set fail attr unsupported type");

# No metadata
my $cfg6 = $cfg_no_metadata->{cache_manager}->getConfiguration(undef, $cfg_no_metadata->{cid}, name_template => 'basic');
$cfg6->{fail} = undef;
ok(! defined($cfg6->getName()), "getName returns undef with missing metadata");
is($cfg6->{fail}, 'getName no metadata tree found', "getName set fail attr with missing metadata");

# Test cache by capturing render failure

done_testing();
