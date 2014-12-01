#
# CCfg test 
#

use strict;
use warnings;

use Test::More;
use myTest qw (eok);
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw ();

use Net::Domain qw(hostname hostdomain);

my $host = hostname();
my $domain = hostdomain();

ok ($host, "Net::Domain::hostname");
ok ($domain, "Net::Domain::hostdomain()");

my $ec = LC::Exception::Context->new->will_store_errors;

is (EDG::WP4::CCM::CCfg::_resolveTags("a"),"a", "_resolveTags(a)");
is (EDG::WP4::CCM::CCfg::_resolveTags('$host'),$host, '_resolveTags($host)');
is (EDG::WP4::CCM::CCfg::_resolveTags('$domain'),$domain, '_resolveTags($domain)');
is (EDG::WP4::CCM::CCfg::_resolveTags('$host$domain'),$host.$domain, '_resolveTags($host$domain)');
is (EDG::WP4::CCM::CCfg::_resolveTags('$hosthost$domaindomain'),$host."host".$domain."domain", '_resolveTags($hosthost$domaindomain)');
is (EDG::WP4::CCM::CCfg::_resolveTags('$host$domain$host$domain'),"$host$domain$host$domain", '_resolveTags($host$domain$host$domain)');
is (EDG::WP4::CCM::CCfg::_resolveTags(':$host/$domain/$host/$domain'),":$host/$domain/$host/$domain", '_resolveTags(:$host/$domain/$host/$domain)');

done_testing();
