# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::Configuration;

use strict;
use POSIX qw (getpid);
use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager qw ($CURRENT_CID_FN);
use EDG::WP4::CCM::Element qw();
#use EDG::WP4::CCM::SyncFile qw (read);
use EDG::WP4::CCM::Path qw ();
use Scalar::Util qw (tainted);

use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw();
our $VERSION = '${project.version}';

=head1 NAME

EDG::WP4::CCM::Configuration - Configuration class

=head1 SYNOPSIS

  $cid = $cfg->getConfigurationId();
  $elt = $cfg->getElement($path);
  $elt = $cfg->getElement($string);
  $val = $cfg->getValue($path);
  $val = $cfg->getValue($string);
  $bool = $cfg->elementExists($path);
  $bool = $cfg->elementExists($string);
  $cfg->lock();
  $cfg->unlock();
  $bool = $cfg->isLocked();

=head1 DESCRIPTION

Module provides the Configuration class, to manipulate confgurations.

=over

=cut

# ------------------------------------------------------

my $ec = LC::Exception::Context->new->will_store_errors;

my $PROFILE_DIR_N = "profile.";
my $ACTIVE_FN = "ccm-active-profile.";

# in this hash we keep track number of open configuration with given
# cid. it is used for creation and removal of pid_files


#
# Create Configuration object. It takes two arguments:
#   $cache_manager - CacheManager object
#   $cid - configuration id
#   $locked - true or false lock flag
#
# active.pid is created in profile.cid directory (where pid is process
# id).
#
# If configuration with specified cid does not exists exception is
# thrown.
#

sub new { #T
  my ($class, $cache_manager, $cid, $locked) = @_;
  my $cache_path = $cache_manager->getCachePath();
  unless ($cache_path =~ m{^([-./\w]+)}) {
    throw_error ("Cache path '$cache_path' is not an absolute path");
    return ();
  }
  $cache_path = $1;
  unless ($cid =~ m{^(\d+)$}) {
    throw_error ("CID '$cid' must be a number");
    return ();
  }
  $cid = $1;
  my $cfg_path = $cache_path."/".$PROFILE_DIR_N.$cid;
  my $self = {"cid" => $cid,
	      "locked" => $locked,
	      "cache_manager" => $cache_manager,
	      "cache_path" => $cache_path,
	      "cfg_path" => $cfg_path,
	      "cid_to_number" => undef
	     };
  unless (-d $cfg_path) {
    throw_error ("configuration directory ($cfg_path) does not exist");
    return();
  }
  bless ($self, $class);
  unless ($self->_create_pid_file ($self)) {
    $ec->rethrow_error();
    return();
  }
  return $self;
}

#
# return configuration path
#

sub getConfigPath {
  my ($self) = @_;
  return $self->{"cfg_path"};
}

#
# return CacheManager
#

sub getCacheManager () {
  my ($self) = @_;
  return $self->{"cache_manager"};
}

#
# sub creates pid file (if needed) in the directory of the configuration
# it updates %cid_to_number
#

sub _create_pid_file { #T
  my ($self) = @_;
  unless ($self->{"cid_to_number"}{$self->{"cid"}}) {
    $self->{"cid_to_number"}{$self->{"cid"}} += 1;
    my $pid_file = $self->{"cfg_path"}."/$ACTIVE_FN".$self->{"cid"}."-".getpid();
    unless (_touch_file ($pid_file)) {
      throw_error ("_touch_file($pid_file)", $ec->error);
      return();
    }
  }
  return SUCCESS;
}

#
# sub removes pid file, if number of opened configuration with
# given cid drops to zero. it updates %cid_to_number
#

sub _remove_pid_file () { #T (indirectly)
  my ($self, $cid) = @_;
  unless (defined ($cid)) {
    throw_error ("_remove_pid_file", "cid parameter not defined");
    return();
  }
  $self->{"cid_to_number"}{$self->{"cid"}} -= 1;
  if ($self->{"cid_to_number"}{$self->{"cid"}} == 0) {
    my $pid_file = $self->{"cfg_path"}."/$ACTIVE_FN".$self->{"cid"}."-".getpid();
    #unless (unlink ($pid_file)) {
    if((-f $pid_file) && !unlink($pid_file)){
      throw_error ("unlink($pid_file)", $!);
      return();
    }
  }
  return SUCCESS;
}

#
# sub creates empty file with $file_name name
#

sub _touch_file ($) { #T
  my ($file_name) = @_;
  unless (open (FILEHANDLE, "+> $file_name")) {
    throw_error ("open ($file_name)",$!);
    return ();
  }
  unless (truncate (FILEHANDLE, 0)) {
    throw_error ("truncate ($file_name)",$!);
    return ();
  }
  unless (close (FILEHANDLE)) {
    throw_error ("close ($file_name)",$!);
    return ();
  }
  return SUCCESS;
}

#
# Destructor method. It unlinks the active.pid file.
#

sub DESTROY { #T (indirectly)
  my ($self) = @_;
  my $cfg_path = $self->{"cfg_path"};
  my $pid_file = $self->{"cfg_path"}."/$ACTIVE_FN".$self->{"cid"}."-".getpid();
  unless ($self->_remove_pid_file($self->{"cid"})) {
    throw_error ('_remove_pid_file($self->{"cid"})', $ec->error);
    return();
  }
  return SUCCESS;
}

=item getConfigurationId ()

Returns configuration id.

=cut

sub getConfigurationId { #T
  my ($self) = @_;
  unless ($self->{"locked"}) {
    unless ($self->_update_cid_pidf()) {
      $ec->rethrow_error();
      return();
    }
  }
  return $self->{"cid"};
}

=item getElement ($path)

Returns Element object identified by $path (path may be a string or
and object of class Path)

=cut

sub getElement {
  my ($self, $path) = @_;
  unless (UNIVERSAL::isa ($path, "EDG::WP4::CCM::Path")) {
    my $ps = $path;
    $path = EDG::WP4::CCM::Path->new ($ps);
    unless ($path) {
      throw_error ("EDG::WP4::CCM::Path->new ($ps)", $ec->error);
      return ();
    }
  }
  unless ($self->{"locked"}) {
    unless ($self->_update_cid_pidf()) {
      $ec->rethrow_error();
      return();
    }
  }
  my $el = EDG::WP4::CCM::Element->createElement ($self, $path);
  unless ($el) {
    throw_error ("EDG::WP4::CCM::Element->createElement ($self, $path)", $ec->error);
    return();
  }
  return $el;
}

=item getValue ($path)

returns value of the element identified by $path

=cut

sub getValue {
    my ($self, $path) = @_;
    my $el  = $self->getElement($path);
    unless ($el) {
	throw_error("$self->getElement($path)",$ec->error);
	return();
    }
    my $val = $el->getValue($path);
    unless (defined ($val)) {
	throw_error("$el->getValue($path)",$ec->error);
	return();
    }
    return ($val);
}

=item elementExists ($path)

returns true if elements identified by $path exists

=cut

sub elementExists {
    my ($self, $path) = @_;
    unless (UNIVERSAL::isa ($path, "EDG::WP4::CCM::Path")) {
	my $ps = $path;
	$path = EDG::WP4::CCM::Path->new ($ps);
	unless ($path) {
	    throw_error ("EDG::WP4::CCM::Path->new ($ps)", $ec->error);
	    return ();
	}
    }
    unless ($self->{"locked"}) {
	unless ($self->_update_cid_pidf()) {
	    $ec->rethrow_error();
	    return();
	}
    }
    my $ex = EDG::WP4::CCM::Element->elementExists ($self, $path);
    unless (defined($ex)) {
	throw_error ("EDG::WP4::CCM::Element->elementExists ($self, $path)", $ec->error);
	return();
    }
    return $ex;
}

#
# subroutine update self->{"cid"} if current.cid contents of current.cid
# are different from it
# if cid changes it also creates new pidfile
#

sub _update_cid_pidf { #T
  my ($self) = @_;
  my $cid = $self->{"cache_manager"}->getCurrentCid();
  unless (defined($cid)) {
    throw_error ('$self->{"cache_manager"}->getCurrentCid()', $ec->error);
    return();
  }
  if ($self->{"cid"} != $cid) {
    unless ($self->_remove_pid_file($self->{"cid"})) {
      $ec->rethrow_error ();
      return();
    }
    $self->{"cid"} = $cid;
    $self->{"cfg_path"} = $self->{"cache_path"}."/".$PROFILE_DIR_N.$cid;
    unless ($self->_create_pid_file()) {
      $ec->rethrow_error ();
      return();
    }
  }
  return SUCCESS;
}

=item lock ()

Lock configuration (local lock).

=cut


sub lock { #T
  my ($self) = @_;
  $self->{"locked"} = 1;
}

=item unlock ()

Unlock configuration (local unlock).

=cut

sub unlock { #T
  my ($self) = @_;
  $self->{"locked"} = 0;
  unless ($self->{"locked"}) {
    unless ($self->_update_cid_pidf()) {
      $ec->rethrow_error();
      return();
    }
  }
  #TODO: events notification
}

=item isLocked ()

Returns true if the configuration is locked, otherwise false

=cut

sub isLocked { #T
  my ($self) = @_;
  return $self->{"locked"};
}

# -------------------------------------------------------

1;

__END__

=back

=head1 AUTHOR

Piotr Poznanski <Piotr.Poznanski@cern.ch>

=head1 VERSION

${project.version}

=cut
