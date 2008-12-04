#!/usr/bin/perl -w

#
# cache CacheManager.pm test script
#
# $Id: test-cachemanager.pl,v 1.11 2006/06/26 14:20:43 gcancio Exp $
#
# Copyright (c) 2001 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

#
# TODO: test default path in the call CacheManager -> new ()
#

BEGIN {unshift(@INC,'/usr/lib/perl')};


use strict;
use Test::More qw(no_plan);
use myTest qw (eok);
use LC::Exception qw(SUCCESS);
use LC::File qw (differ);
use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN 
				      $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::SyncFile qw ();

my $ec = LC::Exception::Context->new->will_store_errors;
my $cp = "/tmp/cm-test";

{
eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"), 
     "EDG::WP4::CCM::CacheManager->new (foo)");

#create dir and file structure

`rm -rf $cp`;

eok ($ec, EDG::WP4::CCM::CacheManager::check_dir($cp, $cp), 
     "CacheManager::check_dir($cp)");

`mkdir $cp`;

ok (EDG::WP4::CCM::CacheManager::check_dir($cp, $cp), 
     "CacheManager::check_dir($cp)");

`mkdir $cp/$DATA_DN`;

my $ccidfn = "$cp/$CURRENT_CID_FN";
my $lcidfn = "$cp/$LATEST_CID_FN";

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"), 
     "EDG::WP4::CCM::CacheManager->new (foo)");

`echo 'no' > $cp/$GLOBAL_LOCK_FN`;

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"), 
     "EDG::WP4::CCM::CacheManager->new (foo)");

`echo '1' > $ccidfn`;

eok ($ec, EDG::WP4::CCM::CacheManager->new ("foo"), 
     "EDG::WP4::CCM::CacheManager->new (foo)");

eok ($ec, EDG::WP4::CCM::CacheManager::check_file ($lcidfn, $lcidfn),
     "EDG::WP4::CCM::CacheManager::check_file ($lcidfn, $lcidfn)");

`echo '1' > $lcidfn`;

ok (EDG::WP4::CCM::CacheManager::check_file ($lcidfn, $lcidfn),
     "EDG::WP4::CCM::CacheManager::check_file ($lcidfn, $lcidfn)");

my $cm;

ok ($cm = EDG::WP4::CCM::CacheManager->new ($cp), 
     "EDG::WP4::CCM::CacheManager->new ($cp)");

is ($cm->isLocked(), 0, "$cm->isLocked()");

`echo 'yes' > $cp/$GLOBAL_LOCK_FN`;

is ($cm->isLocked(), 1, "$cm->isLocked()");

`echo 'foo' > $cp/$GLOBAL_LOCK_FN`;

eok ($ec, $cm->isLocked(), "$cm->isLocked()");

`echo 'no' > $cp/$GLOBAL_LOCK_FN`;

`echo 'yes' > $cp/test_yes`;
`echo 'no' > $cp/test_no`;

ok ($cm->unlock () && !differ ("$cp/test_no","$cp/$GLOBAL_LOCK_FN"), 
    "$cm->unlock()");

ok ($cm->unlock () && !differ ("$cp/test_no","$cp/$GLOBAL_LOCK_FN"), 
    "$cm->unlock()");

ok ($cm->lock () && !differ ("$cp/test_yes","$cp/$GLOBAL_LOCK_FN"), 
    "$cm->lock()");

ok ($cm->lock () && !differ ("$cp/test_yes","$cp/$GLOBAL_LOCK_FN"), 
    "$cm->lock()");

my $ccidf;
ok ($ccidf = EDG::WP4::CCM::SyncFile->new("$ccidfn"), 
    "SyncFile->new($ccidf)");
my $lcidf;
ok ($lcidf = EDG::WP4::CCM::SyncFile->new("$lcidfn"),
    "SyncFile->new($cp/$lcidfn)");

$ccidf->write ("1");
$lcidf->write ("2");

ok ($cm->_set_ccid_to_lcid() && 
    ($lcidf->read() == 2) && ($ccidf->read() == 2),
    "_set_ccid_to_lcid($lcidf, $ccidf)");

ok ($cm->_set_ccid_to_lcid() && 
    ($lcidf->read() == 2) && ($ccidf->read() == 2),
    "_set_ccid_to_lcid($lcidf, $ccidf)");

$ccidf->write ("1");
$lcidf->write ("2");

ok ($cm->unlock () && !differ ("$cp/test_no","$cp/$GLOBAL_LOCK_FN") &&
    ($lcidf->read() == 2) && ($ccidf->read() == 2),
    "$cm->unlock()");

ok ($cm->unlock () && !differ ("$cp/test_no","$cp/$GLOBAL_LOCK_FN") &&
    ($lcidf->read() == 2) && ($ccidf->read() == 2),
    "$cm->unlock()");

eok ($ec, $cm->getLockedConfiguration (0), "$cm->getLockedConfiguration (0)");

`mkdir $cp/profile.1`;
`mkdir $cp/profile.2`;

my $cfg;

ok ($cfg = $cm->getLockedConfiguration (0), "$cm->getLockedConfiguration (0)");
ok ($cfg->getConfigurationId() == 2, "$cfg -> getConfigurationId() == 2");
is ($cfg->isLocked(), 1, "$cfg->isLocked()");
ok ($cfg = $cm->getLockedConfiguration (0,1), "$cm->getLockedConfiguration (0,1)");
ok ($cfg->getConfigurationId() == 1, "$cfg -> getConfigurationId() == 1");
is ($cfg->isLocked(), 1, "$cfg->isLocked()");

ok ($cfg = $cm->getUnlockedConfiguration (0), "$cm->getUnlockedConfiguration (0)");
ok ($cfg->getConfigurationId() == 2, "$cfg -> getConfigurationId() == 2");

is ($cfg->isLocked(), 0, "$cfg->isLocked()");
ok ($cfg = $cm->getUnlockedConfiguration (0,1), "$cm->getUnlockedConfiguration (0,1)");
ok ($cfg->getConfigurationId() == 2, "$cfg -> getConfigurationId() == 2");
is ($cfg->isLocked(), 0, "$cfg->isLocked()");

`mkdir $cp/profile.3`;
`mkdir $cp/profile.4`;

$ccidf->write ("3");
$lcidf->write ("4");

$cm->lock();
ok ($cfg = $cm->_getConfig (0, 0), "cfg->_getConfig (0, 0)");
is ($cfg->getConfigurationId(), 3, "$cfg->getConfigurationId() == 3");
$cm->unlock();
ok ($cfg = $cm->_getConfig (0, 0), "cfg->_getConfig (0, 0)");
is ($cfg->getConfigurationId(), 4, "$cfg->getConfigurationId() == 4");
ok ($lcidf->read() == 4 && $ccidf->read() == 4, 
    "current.cid == 4 &&latest.cid == 4");


#use EDG::WP4::CCM::Path;
#$cfg->getElement ();
#$cfg->getElement (EDG::WP4::CCM::Path->new("/a"));

`echo 1 > $cp/td.txt`;
my $url = "file:///$cp/td.txt";

my $file;
ok ($file = $cm -> cacheFile ($url),
   "$cm -> cacheFile ($url)");
ok ($file = $cm -> cacheFile ($url),
   "$cm -> cacheFile ($url)");
}
`rm -rf $cp`;
