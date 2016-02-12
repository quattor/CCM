# ${license-info}
# ${developer-info}
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
use parent qw(Exporter);
use Readonly;
use File::Temp;

our @EXPORT    = qw();
our @EXPORT_OK = qw($GLOBAL_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN
    $DATA_DN $PROFILE_DIR_N);
our $VERSION   = '${project.version}';

=head1 NAME

EDG::WP4::CCM::CacheManager

=head1 SYNOPSIS

  $cm = EDG::WP4::CCM::CacheManager->new(["/path/to/root/of/cache"]);
  $cfg = $cm->getUnlockedConfiguration($cred[, $cid]);
  $cfg = $cm->getLockedConfiguration($cred[, $cid]);
  $cfg = $cm->getAnonymousConfiguration($cred[, $cid]);
  $bool = $cm->isLocked();

=head1 DESCRIPTION

Module provides CacheManager class. This is the top level class
of the NVA-API library. It is used by the clients to interact with
the NVA cache.

=over

=cut

# ------------------------------------------------------

my $ec = LC::Exception::Context->new->will_store_errors;

Readonly our $GLOBAL_LOCK_FN => "global.lock";
Readonly our $CURRENT_CID_FN => "current.cid";
Readonly our $LATEST_CID_FN  => "latest.cid";
Readonly our $DATA_DN        => "data";
Readonly our $PROFILE_DIR_N  => "profile.";

Readonly my $LOCKED => "yes";
Readonly my $UNLOCKED => "no";

=item new ($cache_path)

Create new CacheManager object with C<$cache_path>.

C<$config_file> is an optional parameter that points
to the CCM config file.

=cut

sub new
{    #T
    my ($class, $cache_path, $config_file) = @_;

    initCfg($config_file);

    unless (defined($cache_path)) {
        $cache_path = getCfgValue("cache_root");
    }

    unless (_check_type("directory", $cache_path, "main cache")) {
        $ec->rethrow_error();
        return ();
    }

    my $gl = "$cache_path/$GLOBAL_LOCK_FN";
    my $cc = "$cache_path/$CURRENT_CID_FN";
    my $lc = "$cache_path/$LATEST_CID_FN";

    my $self = {
        "cache_path" => $cache_path,
        "data_path"  => "$cache_path/$DATA_DN",

        "lock_wait"        => getCfgValue("lock_wait"),
        "lock_retries"     => getCfgValue("lock_retries"),
        "get_timeout"      => getCfgValue("get_timeout"),
        "retrieve_retries" => getCfgValue("retrieve_retries"),
        "retrieve_wait"    => getCfgValue("retrieve_wait"),
    };
    $self->{"global_lock_file"} = EDG::WP4::CCM::SyncFile->new($gl);
    $self->{"current_cid_file"} = EDG::WP4::CCM::SyncFile->new($cc);
    $self->{"latest_cid_file"}  = EDG::WP4::CCM::SyncFile->new($lc);

    unless (_check_type("directory", $self->{"data_path"}, "data")
        && _check_type("file", $gl, "global.lock")
        && _check_type("file", $cc, "current.cid")
        && _check_type("file", $lc, "latest.cid"))
    {
        $ec->rethrow_error();
        return ();
    }

    bless($self, $class);
    return $self;
}


# refined check for checking type=file or type=directory access
sub _check_type
{
    my ($type, $obj, $name) = @_;

    if (-e $obj && (($type eq "directory" && -d $obj) || ($type eq "file" && -f $obj) )) {
        return SUCCESS;
    } elsif($!{ENOENT}) {
        throw_error("$name $type does not exist ($type $obj)");
        return ();
    } elsif($!{EACCES}) {
        throw_error("No permission for $name $type ($type $obj)");
        return ();
    } else {
        throw_error("Something wrong while trying to accessing $name $type ($type $obj): $!");
        return ();
    }
}

=item getCachePath

returns path of the cache

=cut

sub getCachePath
{
    my ($self) = @_;
    return $self->{"cache_path"};
}

=item getConfigurationPath

For given C<cid>, return the basepath of the Configuration data.
(No checks are made e.g. if the directory exists,
simply returns the directory name).

=cut

sub getConfigurationPath
{
    my ($self, $cid) = @_;

    my $cache_path = $self->getCachePath();

    return "$cache_path/$PROFILE_DIR_N$cid";
}

=item getCids

Return arrayref to sorted list of all found/valid CIDs.

Returns undef in case of problem.

=cut

sub getCids
{
    my ($self) = @_;

    my $cache_path = $self->getCachePath();

    my $cid_pattern = '(?:^|/)' . $PROFILE_DIR_N . '(\d+)$';

    opendir my $dir, $cache_path or return;

    my @cids = sort # sorted list
        map { m/$cid_pattern/; $1 } # match and return CIDs
        grep { m/$cid_pattern/ && -d "$cache_path/$_" } # match and test for directory
        readdir($dir); # looking for CID subdirectories in cache_path

    close($dir);

    return \@cids;
}

=item getCid

For given C<cid>, validate and check the CID.

Returns undef for a non-existing CID.

Also handles special values for C<cid>:

=over

=item undef, "current" or empty string

If CID is undef, the string "current" or an empty string, the current CID
(from the "current.cid" file) is returned.

=item "latest" or "-"

If CID is the string "latest" or "-", the latest CID
(from the "latest.cid" file) is returned.

=item negative value (e.g. -1)

If CID is negative C<-N>, the N-th most recent CID value is returned
(e.g. -1 returns the most recent CID, -2 the CID before the most recent, ...).

(A distinction is made between "most recent" and "latest", as the "latest" CID
is held in the "latest.cid" file).

=back

=cut

sub getCid
{
    my ($self, $cid) = @_;

    my $valid_cids = $self->getCids();

    if((!defined($cid)) || $cid eq "" || $cid eq "current") {
        $cid = $self->getCurrentCid();
    } elsif($cid eq "latest" || $cid eq "-") {
        $cid = $self->getLatestCid();
    }

    # Return if cid is not a signed integer at this point
    return if ($cid !~ m/^-?\d+$/);

    if ($cid < 0) {
        # TODO: -1 should be equal to getLatestCid?
        my $ind = $cid + scalar @$valid_cids;

        # TODO: or set to oldest?
        return if ($ind < 0);

        $cid = $valid_cids->[$ind];
    }

    if (grep {$_ == $cid} @$valid_cids) {
        return $cid ;
    } else {
        # Whatever it is, it's not a valid cid
        return;
    }
}

=item getConfiguration ($cred, $cid)

Returns narrowest-possible Configuration object.

If C<cid> is defined, return a locked Configuration with this C<cid>.
(Special values for C<cid> are handled by the C<getCid> method).

If C<cid> is undefined, an unlocked Configuration is used (and the write permission
for the anonymous flag are checked against the CacheManager's current CID).

The Configuration instance is created with anonymous flag equal to C<-1>
(i.e. the Configuration instance will determine if the Configuration
is anonymous or not based on the write permissions of the current process).

The C<locked> and C<anonymous> flags can also be forced via named arguments (e.g.
C<<locked => 1>> or C<<anonymous => 1>>).

Security and C<$cred> parameter meaning are not defined
(but is kept for compatibility with other
C<get{Locked,Unlock,Anonymous}Configuration> methods).

=cut

sub getConfiguration
{
    my ($self, $cred, $cid, %opts) = @_;

    my ($anonymous, $locked);

    if(exists($opts{anonymous})) {
        $anonymous = $opts{anonymous};
    } else {
        $anonymous = -1;
    };

    if(exists($opts{locked})) {
        $locked = $opts{locked};
    } else {
        $locked = defined($cid) ? 1 : 0;
    }

    my $actual_cid = $self->getCid($cid);
    if (! defined($actual_cid)) {
        throw_error("can't getConfiguration with invalid cid '$cid'");
        return ();
    }

    my $cfg = $self->_getConfig($locked, $cred, $actual_cid, $anonymous);
    unless (defined($cfg)) {
        $ec->rethrow_error();
        return ();
    }
    return $cfg;
}

=item getUnlockedConfiguration ($cred; $cid)

This method is deprecated in favour of C<getConfiguration>.

Returns unlocked Configuration object.

Unless the object is locked explicitly later by calling the C<lock> method,
C<CCM::Element>s will always be fetched from the current CID,
not the CID passed via C<$cid>. (If the $cid parameter is omitted,
the most recently downloaded configuration (when the cache
was not globally locked) is returned.)

Security and $cred parameter meaning are not defined.

=cut

sub getUnlockedConfiguration
{    #T
    my ($self, $cred, $cid) = @_;
    my $cfg = $self->_getConfig(0, $cred, $cid);
    unless (defined($cfg)) {
        $ec->rethrow_error();
        return ();
    }
    return $cfg;
}

=item getLockedConfiguration ($cred; $cid)

This method is deprecated in favour of C<getConfiguration>.

Returns locked Configuration object. If the $cid parameter is
omitted, the most recently downloaded configuration (when the cache
was not globally locked) is returned.

Security and $cred parameter meaning are not defined.

=cut

sub getLockedConfiguration
{    #T
    my ($self, $cred, $cid) = @_;
    my $cfg = $self->_getConfig(1, $cred, $cid);
    unless (defined($cfg)) {
        $ec->rethrow_error();
        return ();
    }
    return $cfg;
}

=item getAnonymousConfiguration ($cred; $cid)

This method is deprecated in favour of C<getConfiguration>.

Returns unlocked anonymous Configuration object.

Unless the object is locked explicitly later by calling the C<lock> method,
C<CCM::Element>s will always be fetched from the current CID,
not the CID passed via C<$cid>. (If the $cid parameter is omitted,
the most recently downloaded configuration (when the cache
was not globally locked) is returned.)

Security and $cred parameter meaning are not defined.

=cut

sub getAnonymousConfiguration
{    #T
    my ($self, $cred, $cid) = @_;
    my $cfg = $self->_getConfig(0, $cred, $cid, 1);
    unless (defined($cfg)) {
        $ec->rethrow_error();
        return ();
    }
    return $cfg;
}

#
# returns configuration
# $lc - locked/unlocked config
# $cred - credential [unused / unsupported in current code; pass undef]
# $cid - (optional) configuration id (use current CID if undefined)
# $anonymous - (optional) anonymous flag
#

sub _getConfig
{    #T
    my ($self, $lc, $cred, $cid, $anonymous) = @_;
    my $locked = $self->isLocked();
    unless (defined($locked)) {
        throw_error("$self->isLocked()", $ec->error);
        return ();
    }

    unless (defined($cid)) {
        $cid = $self->getCurrentCid();
        unless (defined($cid)) {
            $ec->rethrow_error();
            return ();
        }
    }

    my $cfg = EDG::WP4::CCM::Configuration->new($self, $cid, $lc, $anonymous);
    unless (defined($cfg)) {
        $ec->rethrow_error();
        return ();
    }
    return $cfg;
}

=item isLocked ()

Returns true if the cache is globally locked, otherwise false.

=cut

sub isLocked
{    #T
    my ($self) = @_;
    my $locked = $self->{"global_lock_file"}->read();
    unless (defined($locked)) {
        throw_error("read (" . $self->{"global_lock_file"}->get_file_name . ")", $ec->error);
        return ();
    }
    if    ($locked eq $LOCKED)   {return 1;}
    elsif ($locked eq $UNLOCKED) {return 0;}
    else {
        throw_error(
            "bad contents of " . $self->{"global_lock_file"}->get_file_name() . " ($locked)");
        return ();
    }
}


#
# _encodeUrl ($url)
#

sub _encodeUrl
{
    my ($url) = @_;
    my $eu = encode_base64($url, "");
    $eu =~ s/\//_/g;
    return $eu;
}


=item getCurrentCid

returns current cid (from cid file)

=cut

sub getCurrentCid
{
    my ($self) = @_;
    my $cid = $self->{"current_cid_file"}->read();
    unless (defined($cid)) {
        throw_error('$self->{"current_cid_file"}}->read()', $ec);
        return ();
    }
    return $cid;
}

=item getLatestCid

returns latest cid (from cid file)

=cut

sub getLatestCid
{
    my ($self) = @_;
    my $cid = $self->{"latest_cid_file"}->read();
    unless (defined($cid)) {
        throw_error('$self->{"latest_cid_file"}}->read()', $ec);
        return ();
    }
    return $cid;
}

=pod

=back

=cut

1;
