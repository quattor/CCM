#!/usr/bin/perl -w

#
# cache Path.pm test script
#
# $Id: test-ccfg.pl,v 1.3 2006/06/26 14:20:43 gcancio Exp $
#
# Copyright (c) 2001 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

BEGIN {unshift(@INC,'/usr/lib/perl')};


use strict;
use Test::More qw(no_plan);
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
