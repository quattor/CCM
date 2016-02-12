# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::Configuration;

use strict;
use warnings;

use POSIX qw (getpid);
use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Element;
use CAF::FileWriter;

use EDG::WP4::CCM::Path;

use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw();
our $VERSION   = '${project.version}';

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

our $ec = LC::Exception::Context->new->will_store_errors;

=item new

Create Configuration object. It takes three arguments:
    C<cache_manager>: the CacheManager object
    C<cid>: the configuration id
    C<locked>: boolean lock flag
    C<anonymous>: boolean anonymous flag

If a configuration with specified CID does not exists, an exception is
thrown.

When the C<locked> flag is set (or when the C<lock> method is called to set it),
the Configuration instance is bound to the specific CID, even if this is not
the CacheManager's current one (e.g. when a new profile is fetched during the lifetime
of the process, the CacheManager current CID is updated to the latest one).
The locking is relevant when a C<CCM::Element> is accessed via
a C<CCM::Configuration> instance (in particular, when a call to C<_prepareElement>
is made).
As a consequence, an unlocked Configuration instance will always use the
CacheManager's current CID.

Unless the anonymous flag is set to true, each process that creates a
Configuration instance, creates a file named C<ccm-active-profile.$cid.$pid>
(with C<$cid> the CID and C<$pid> the process ID) under the C<profile.$cid>
directory in the C<CacheManager> cache path. The presence of this file protects
the process from getting this particular CID removed by the C<ccm-purge> command
(e.g. by the daily purge cron job).
If the anonymous flag is set to -1, the permissions of the user to create this file
are verified, and if the user can write to this file, the anonymous flag is set to
false (this is only verified once during initialisation).

Processes that have no permission to create this file (or don't care about long
runtimes), can set the C<anonymous> flag and use the configuration
(at their own risk).

=cut

sub new
{    #T
    my ($class, $cache_manager, $cid, $locked, $anonymous) = @_;

    my $cache_path = $cache_manager->getCachePath();
    unless ($cache_path =~ m{^([-./\w]+)}) {
        throw_error("Cache path '$cache_path' is not an absolute path");
        return ();
    }
    $cache_path = $1;

    unless ($cid =~ m{^(\d+)$}) {
        throw_error("CID '$cid' must be a number");
        return ();
    }
    $cid = $1;

    my $cfg_path = $cache_manager->getConfigurationPath($cid);
    unless (-d $cfg_path) {
        throw_error("configuration directory ($cfg_path) does not exist");
        return ();
    }

    my $self     = {
        "cid"           => $cid,
        "locked"        => $locked,
        "cache_manager" => $cache_manager,
        "cache_path"    => $cache_path,
        "cfg_path"      => $cfg_path,
        "cid_to_number" => undef, # counter to keep track of number of times a CID is in use
        "anonymous"     => defined($anonymous) ? $anonymous : 0, # clean 0
    };

    bless($self, $class);

    $self->{anonymous} = ($self->_can_create_pid_file() ? 0 : 1)
        if ($self->{anonymous} == -1);

    unless ($self->_create_pid_file()) {
        $ec->rethrow_error();
        return ();
    }
    return $self;
}

#
# return configuration path
#

sub getConfigPath
{
    my ($self) = @_;
    return $self->{"cfg_path"};
}

#
# return CacheManager
#

sub getCacheManager
{
    my ($self) = @_;
    return $self->{"cache_manager"};
}

# returns the pid filename for cid
sub _pid_filename
{
    my ($self, $cid) = @_;

    $cid = $self->{"cid"} if (!defined($cid));
    return $self->{"cfg_path"} . "/ccm-active-profile.${cid}-" . getpid();
}

# Return if current process can create the pid file in the
# directory of the configuration or not.
# It does this by trying to create an empty file
# with as filename the pid_filename with additional '.writetest' suffix.
# This test file is removed afterwards.
# If cleanup fails, error is thrown and failure status via undef is returned.
sub _can_create_pid_file
{
    my ($self) = @_;

    my $fn = $self->_pid_filename($self->{"cid"}) . ".writetest";

    unless (_touch_file($fn)) {
        $ec->ignore_error();
        return 0;
    }

    if ((-f $fn) && ! unlink($fn)) {
        throw_error("unlink($fn)", $!);
        return;
    }

    return 1;
};

#
# sub creates pid file (if needed) in the directory of the configuration
# it updates %cid_to_number
#

sub _create_pid_file
{    #T
    my ($self) = @_;
    unless ($self->{"cid_to_number"}{$self->{"cid"}}) {
        $self->{"cid_to_number"}{$self->{"cid"}} += 1;

        return SUCCESS if $self->{anonymous};

        my $pid_file = $self->_pid_filename();
        unless (_touch_file($pid_file)) {
            $ec->rethrow_error();
            return ();
        }
    }

    return SUCCESS;
}

#
# sub removes pid file, if number of opened configuration with
# given cid drops to zero. it updates %cid_to_number
#

sub _remove_pid_file
{    #T (indirectly)
    my ($self, $cid) = @_;
    unless (defined($cid)) {
        throw_error("_remove_pid_file", "cid parameter not defined");
        return ();
    }
    $self->{"cid_to_number"}{$cid} -= 1;
    if ($self->{"cid_to_number"}{$cid} == 0) {

        return SUCCESS if $self->{anonymous};

        my $pid_file = $self->_pid_filename($cid);
        if ((-f $pid_file) && !unlink($pid_file)) {
            throw_error("unlink($pid_file)", $!);
            return ();
        }
    }
    return SUCCESS;
}

#
# sub creates empty file with $file_name name
#

sub _touch_file
{    #T
    my ($file_name) = @_;
    my $fh = CAF::FileWriter->new($file_name);
    print $fh '';
    $fh->close();

    my $err = $ec->error();
    if(defined($err)) {
        $ec->ignore_error();
        throw_error("_touch_file($file_name) failed ", $err->reason);
        return;
    }

    return SUCCESS;
}

#
# Destructor method. It unlinks the active.pid file.
#

sub DESTROY
{    #T (indirectly)
    my ($self) = @_;
    unless ($self->_remove_pid_file($self->{"cid"})) {
        throw_error('_remove_pid_file($self->{"cid"})', $ec->error);
        return ();
    }
    return SUCCESS;
}

=item getConfigurationId ()

Returns configuration id.

=cut

# triggers a _update_cid_pidf for unlocked configs
sub getConfigurationId
{    #T
    my ($self) = @_;
    unless ($self->{"locked"}) {
        unless ($self->_update_cid_pidf()) {
            $ec->rethrow_error();
            return ();
        }
    }
    return $self->{"cid"};
}

# Obtain the current CID from the CacheManager and
# update C<cid> attribute with current CID if needed.
# The update includes changing the C<cfg_path> attribute
# and updating the pid/CID files and counters using
# <_remove_pid_file(old_CID)> and C<_create_pid_file>
# (which uses the new/updated C<cid> attribute).
sub _update_cid_pidf
{    #T
    my ($self) = @_;
    my $cid = $self->{cache_manager}->getCurrentCid();
    unless (defined($cid)) {
        throw_error('$self->{"cache_manager"}->getCurrentCid()', $ec->error);
        return ();
    }
    if ($self->{"cid"} != $cid) {
        unless ($self->_remove_pid_file($self->{"cid"})) {
            $ec->rethrow_error();
            return ();
        }
        $self->{"cid"}      = $cid;
        $self->{"cfg_path"} = $self->{cache_manager}->getConfigurationPath($cid);
        unless ($self->_create_pid_file()) {
            $ec->rethrow_error();
            return ();
        }
    }
    return SUCCESS;
}

=item lock ()

Lock configuration (local lock).

=cut

sub lock
{    #T
    my ($self) = @_;
    $self->{"locked"} = 1;
    return SUCCESS;
}

=item unlock ()

Unlock configuration (local unlock).

=cut

sub unlock
{    #T
    my ($self) = @_;
    $self->{"locked"} = 0;
    unless ($self->_update_cid_pidf()) {
        $ec->rethrow_error();
        return ();
    }

    #TODO: events notification
    return SUCCESS;
}

=item isLocked ()

Returns true if the configuration is locked, otherwise false

=cut

sub isLocked
{    #T
    my ($self) = @_;
    return $self->{"locked"};
}

# _prepareElement prepares for accessing the actual
# profile data via the EDG::WP4::CCM::Element class.
# It converts the C<path> argument to a CCM::Path instance
# (if needed) and updates the CID to the latest available
# if the configuration is not locked.
# Returns a CCM::Path instance on success
# (or undef in case of problem).
sub _prepareElement
{
    my ($self, $path) = @_;

    unless (UNIVERSAL::isa($path, "EDG::WP4::CCM::Path")) {
        my $ps = $path;
        $path = EDG::WP4::CCM::Path->new($ps);
        unless ($path) {
            throw_error("EDG::WP4::CCM::Path->new ($ps)", $ec->error);
            return;
        }
    }

    unless ($self->{"locked"}) {
        unless ($self->_update_cid_pidf()) {
            $ec->rethrow_error();
            return;
        }
    }

    return $path;
}

=item getElement ($path)

Returns Element object identified by $path (path may be a string or
and object of class Path)

=cut

sub getElement
{
    my ($self, $path) = @_;

    $path = $self->_prepareElement($path);
    unless (defined($path)) {
        $ec->rethrow_error();
        return ();
    }

    # Actual access to the data happens here
    my $el = EDG::WP4::CCM::Element->createElement($self, $path);
    unless ($el) {
        throw_error("EDG::WP4::CCM::Element->createElement ($self, $path)", $ec->error);
        return ();
    }
    return $el;
}

=item getValue ($path)

returns value of the element identified by $path

=cut

sub getValue
{
    my ($self, $path) = @_;
    my $el = $self->getElement($path);
    unless ($el) {
        throw_error("$self->getElement($path)", $ec->error);
        return ();
    }
    my $val = $el->getValue($path);
    unless (defined($val)) {
        throw_error("$el->getValue($path)", $ec->error);
        return ();
    }
    return ($val);
}

=item elementExists ($path)

returns true if elements identified by $path exists

=cut

sub elementExists
{
    my ($self, $path) = @_;

    $path = $self->_prepareElement($path);
    unless (defined($path)) {
        $ec->rethrow_error();
        return ();
    }

    # Actual access to the data happens here
    my $ex = EDG::WP4::CCM::Element->elementExists($self, $path);
    unless (defined($ex)) {
        throw_error("EDG::WP4::CCM::Element->elementExists ($self, $path)", $ec->error);
        return ();
    }
    return $ex;
}

# Handle failures. Stores the error message and
# returns undef. All failures should use 'return $self->fail("message");'.
# No error logging should occur in this module.
# Based on CAF::Object->fail
sub fail
{
    my ($self, @messages) = @_;
    $self->{fail} = join('', map {defined($_) ? $_ : '<undef>'} @messages);
    return;
}


=item getTree ($path)

returns C<getTree> of the element identified by C<$path>.
Any other optional arguments are passed to C<getTree>.

If the path does not exist, undef is returned. (Any error
reason is set as the C<fail> attribute and the error is ignored.)

=cut

sub getTree
{
    my ($self, $path, @args) = @_;

    my $res;
    if ($self->elementExists($path)) {
        my $el = $self->getElement($path);
        if ($el) {
            $res = $el->getTree(@args);
        }
    }

    if ($ec->error()) {
        my $reason = $ec->error()->reason();
        $ec->ignore_error();
        return $self->fail($reason);
    }

    return $res;
}

=pod

=back

=cut

1;
