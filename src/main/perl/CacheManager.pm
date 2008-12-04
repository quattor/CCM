# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::CacheManager;

use strict;
use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::SyncFile qw();
use EDG::WP4::CCM::Configuration qw();
use EDG::WP4::CCM::CCfg qw(initCfg getCfgValue);
use MIME::Base64 qw(encode_base64);
use LWP::UserAgent;
use HTTP::Status;

use File::Temp;

BEGIN{

 use      Exporter;
 use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

 @ISA       = qw(Exporter);
 @EXPORT    = qw();           
 @EXPORT_OK = qw($GLOBAL_LOCK_FN $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN);
 $VERSION = sprintf("%d.%02d", q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/);
}

=head1 NAME

EDG::WP4::CCM::CacheManager

=head1 SYNOPSIS

  $cm = EDG::WP4::CCM::CacheManager->new(["/path/to/root/of/cache"]);
  $cfg = $cm->getUnlockedConfiguration($cred[, $cid]);
  $cfg = $cm->getLockedConfiguration($cred[, $cid]);
  $cm->lock($cred);
  $cm->unlock($cred);
  $bool = $cm->isLocked();

=head1 DESCRIPTION

Module provides CacheManager class. This is the top level class
of the NVA-API library. It is used by the clients to interact with
the NVA cache.

=over

=cut

# ------------------------------------------------------

my $ec = LC::Exception::Context->new->will_store_errors;

use vars qw ($GLOBAL_LOCK_FN $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN
	    $config);

$GLOBAL_LOCK_FN = "global.lock";
$CURRENT_CID_FN = "current.cid";
$LATEST_CID_FN  = "latest.cid";
$DATA_DN        = "data";
my $LOCKED      = "yes";
my $UNLOCKED    = "no";

=item new ($cache_path)

Create new CacheManager object. 
$config_file is an optional parameter that points to the ccc.conf file.

=cut

sub new { #T
  my ($class, $cache_path) = @_;

  initCfg();

  unless (defined ($cache_path)) {
    $cache_path = getCfgValue("cache_root");
  }


  unless (check_dir ($cache_path, "main cache")) {
    $ec->rethrow_error();
    return();
  }

  my $gl = "$cache_path/$GLOBAL_LOCK_FN";
  my $cc = "$cache_path/$CURRENT_CID_FN";
  my $lc = "$cache_path/$LATEST_CID_FN";

  my $self = {"cache_path"       => $cache_path,
	      "data_path"        => "$cache_path/$DATA_DN",

	      "lock_wait"        => getCfgValue ("lock_wait"),
	      "lock_retries"     => getCfgValue ("lock_retries"),
	      "get_timeout"      => getCfgValue ("get_timeout"),
	      "retrieve_retries" => getCfgValue ("retrieve_retries"),
	      "retrieve_wait"    => getCfgValue ("retrieve_wait"),
	     }; 
  $self->{"global_lock_file"} = EDG::WP4::CCM::SyncFile->new($gl);
  $self->{"current_cid_file"} = EDG::WP4::CCM::SyncFile->new($cc);
  $self->{"latest_cid_file"}  = EDG::WP4::CCM::SyncFile->new($lc);

  unless (check_dir ($self->{"data_path"},"data") && 
	 check_file ($gl, "global.lock") &&
	 check_file ($cc, "current.cid") &&
	 check_file ($lc, "latest.cid")) {
    $ec->rethrow_error();
    return();
  }
 
  bless ($self, $class);
  return $self;
}

sub check_dir ($$) { #T
  my ($dir, $name) = @_;
  if (-d $dir) {
    return SUCCESS;
  } else {
    throw_error ("$name directory does not exist");
    return();
  }
}

sub check_file ($$) { #T
  my ($file, $name) = @_;
  if (-f $file) {
    return SUCCESS;
  } else {
    throw_error ("$name file does not exist");
    return();
  }
}


#
# returns path of the cache
#

sub getCachePath {
  my ($self) = @_;
  return $self->{"cache_path"};
}


=item fetchForeignProfile ($host)
=cut
sub fetchForeignProfile { 
}
=item getUnlockedConfiguration ($cred; $cid)

Returns unlocked Configuration object. If the $cid parameter is
ommited, the most recently downloaded configuration (when the cache
was not globally locked) is returned.

Security and $cred parameter meaning are not defined.

=cut

sub getUnlockedConfiguration { #T
  my ($self, $cred, $cid) = @_;
  my $cfg = $self->_getConfig (0, $cred, $cid);
  unless (defined ($cfg)) {
    $ec->rethrow_error();
    return ();
  }
  return $cfg;
}

=item getLockedConfiguration ($cred; $cid)

Returns locked Configuration object. If the $cid parameter is
ommited, the most recently downloaded configuration (when the cache
was not globally locked) is returned.

Security and $cred parameter meaning are not defined.

=cut

sub getLockedConfiguration { #T
  my ($self, $cred, $cid) = @_;
  my $cfg = $self->_getConfig (1, $cred, $cid);
  unless (defined ($cfg)) {
    $ec->rethrow_error();
    return ();
  }
  return $cfg;
}

#
# returns configuration
# $lc - locked/unlocked config
# $cred - credential
# $cid - (optional) configuration id
#

sub _getConfig { #T
  my ($self, $lc, $cred, $cid) = @_;
  my $locked = $self->isLocked();
  unless (defined ($locked)) {
    throw_error ("$self->isLocked()", $ec->error);
   return();
  } 
#  if (!$locked) {
#     unless($self->_set_ccid_to_lcid()) {
#       throw_error ("$self->_set_ccid_to_lcid()", $ec->error);
#       return();
#     }   
#  }
  unless (defined ($cid)) {
    $cid = $self->{"current_cid_file"}->read();
    unless (defined ($cid)) {
      throw_error ('$self{"current_cid_file"}->read()', $ec->error);
      return ();
    }
  }

  my $cfg = EDG::WP4::CCM::Configuration->new ($self, $cid, $lc);
  unless (defined ($cfg)) {
      $ec->rethrow_error();
      return();
  }
  return $cfg;
}

=item lock ($cred)

Lock cache globally.

Security and $cred parameter meaning are not defined.

=cut

#TOC: lock and unlock have unsymetric behaviour is it ok?

sub lock { #T

    throw_error ("function is not implemented");
    return();

  my ($self, $cred) = @_;
  unless ($self->{"global_lock_file"}->write($LOCKED)) {
    throw_error ("write (".$self->{"global_lock_file"}->get_file_name().")", 
		 $ec->error);
    return();
  }
  return SUCCESS;
}

=item unlock ($cred)

Unlock cache globally.

Security and $cred parameter meaning are not defined.

=cut

sub unlock { #T

    throw_error ("function is not implemented");
    return();

  my ($self, $cred) = @_;
  my $locked = $self->isLocked ();
  unless (defined ($locked)) {
    throw_error ("isLocked()",$ec->error);
    return();
  }
  if ($locked) {
    unless($self->_set_ccid_to_lcid()) {
      throw_error ("$self->_set_ccid_to_lcid()", $ec->error);
      return();
    }
    unless ($self->{"global_lock_file"}->write($UNLOCKED)) {
      throw_error ("write (".$self->{"global_lock_file"}->get_file_name().")", 
		   $ec->error);
      return();
    }
  }
  return SUCCESS;
}

#
# subroutine sets current.cid to latest.cid (if they are different)
#

sub _set_ccid_to_lcid { #T


    throw_error ("this function should't be called in current implemenation");
    return();

# TODO: investigate one extra new-line character at the end
#       of current.cid

  my ($self) = @_;
  my $lcidf = $self->{"latest_cid_file"};
  my $ccidf = $self->{"current_cid_file"};

  my $lcid = $lcidf->read();
  unless (defined $lcid) {
    throw_error ('$lcidf->read()',$ec->error);
    return();
  }
  my $ccid = $ccidf->read();
  unless (defined ($ccid)) {
    throw_error ('$ccidf->read()',$ec->error);
    return();
  }
  unless ($ccid == $lcid) {
    unless ($ccidf->write("$lcid")) {
     throw_error ('$self->{"$ccidf->write($lcid)',$ec->error);
     return();
    }
  }
  return SUCCESS;
}

=item isLocked ()

Returns true if the cache is globally locked, otherwise false.

=cut

sub isLocked { #T
  my ($self) = @_;
  my $locked = $self->{"global_lock_file"}->read();
  unless (defined ($locked)) {
    throw_error ("read (".$self->{"global_lock_file"}->get_file_name.")", 
		 $ec->error);
    return();
  }
  if ($locked eq $LOCKED) {return 1;}
  elsif ($locked eq $UNLOCKED) {return 0;}
  else {
    throw_error ("bad contents of " . 
		 $self->{"global_lock_file"}->get_file_name(). 
		 " ($locked)");
    return();
  }
}

#
# public info?
# cacheFile ($url)
#

sub cacheFile { #T
  my ($self, $url) = @_;
  my $eu = _encodeUrl($url);
  unless($eu){
    throw_error ("_encodeUrl($url)",$!);
    return();
  }
  
  my $fn = $self->{"cache_path"}."/data/$eu";
  my $ua = LWP::UserAgent -> new ();

  #TODO retries/wait

  $ua->timeout($self->{"get_timeout"});
  my $req = HTTP::Request -> new (GET=>$url);

  my $mtime;
  if (-f $fn) {
    $mtime = (stat($fn))[9];
    unless (defined ($mtime)) {
      throw_error ("stat($fn)", $!);
      return();
    }
    $req->headers->if_modified_since($mtime);
  }
  my $success = 0;
  my $i = 0;
  my $res;
  while (!$success && ($i < $self->{"retrieve_retries"})) {
    $res = $ua->request($req, $fn);
    if ($res->is_success) {
      $success = 1; #was downloaded
      $mtime=$res->last_modified;
      unless (utime($mtime, $mtime, $fn)) {
	throw_error ("utime($mtime, $mtime, $fn)",$!);
	return();
      }
    } elsif ($res->code == RC_NOT_MODIFIED) {
      $success = 1; #was not downloaded, becasue it is cache and unmodified
    } else {
      sleep ($self->{"retrieve_wait"});
      $i++;
    }
  }
  unless ($success){
    throw_error ("http request failed",$res->code);
    return();
  }
  return $fn;
}

#
# _encodeUrl ($url)
#

sub _encodeUrl ($) {
  my ($url) = @_;
  my $eu = encode_base64($url,"");
  $eu =~ s/\//_/g;
  return $eu;
}

#
# returns current cid (from cid file)
#

sub getCurrentCid {
  my ($self) = @_;
  my $cid = $self->{"current_cid_file"}->read();
  unless (defined ($cid)){
    throw_error ('$self->{"current_cid_file"}}->read()', $ec);
    return();
  }
  return $cid;
}

# ------------------------------------------------------

1;

__END__

=back

=head1 AUTHOR

Piotr Poznanski <Piotr.Poznanski@cern.ch>

=head1 VERSION

$Id: CacheManager.pm.cin,v 1.4 2008/03/11 16:59:22 munoz Exp $

=cut
