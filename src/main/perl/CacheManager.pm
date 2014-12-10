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

use File::Temp;

our @EXPORT    = qw();
our @EXPORT_OK = qw($GLOBAL_LOCK_FN $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN);
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

our $GLOBAL_LOCK_FN = "global.lock";
our $CURRENT_CID_FN = "current.cid";
our $LATEST_CID_FN  = "latest.cid";
our $DATA_DN        = "data";
my $LOCKED   = "yes";
my $UNLOCKED = "no";

=item new ($cache_path)

Create new CacheManager object. 
$config_file is an optional parameter that points to the ccc.conf file.

=cut

sub new
{    #T
    my ($class, $cache_path) = @_;

    initCfg();

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

#
# returns path of the cache
#

sub getCachePath
{
    my ($self) = @_;
    return $self->{"cache_path"};
}

=item getUnlockedConfiguration ($cred; $cid)

Returns unlocked Configuration object. If the $cid parameter is
ommited, the most recently downloaded configuration (when the cache
was not globally locked) is returned.

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

Returns locked Configuration object. If the $cid parameter is
ommited, the most recently downloaded configuration (when the cache
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

Returns unlocked anonymous Configuration object. 
If the $cid parameter is ommited, the most recently 
downloaded configuration (when the cache
was not globally locked) is returned.

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
# $cred - credential
# $cid - (optional) configuration id
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
        $cid = $self->{"current_cid_file"}->read();
        unless (defined($cid)) {
            throw_error('$self{"current_cid_file"}->read()', $ec->error);
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
# public info?
# cacheFile ($url)
#

sub cacheFile
{    #T
    my ($self, $url) = @_;
    my $eu = _encodeUrl($url);
    unless ($eu) {
        throw_error("_encodeUrl($url)", $!);
        return ();
    }

    my $fn = $self->{"cache_path"} . "/data/$eu";
    my $ua = LWP::UserAgent->new();

    #TODO retries/wait

    $ua->timeout($self->{"get_timeout"});
    my $req = HTTP::Request->new(GET => $url);

    my $mtime;
    if (-f $fn) {
        $mtime = (stat($fn))[9];
        unless (defined($mtime)) {
            throw_error("stat($fn)", $!);
            return ();
        }
        $req->headers->if_modified_since($mtime);
    }
    my $success = 0;
    my $i       = 0;
    my $res;
    while (!$success && ($i < $self->{"retrieve_retries"})) {
        $res = $ua->request($req, $fn);
        if ($res->is_success) {
            $success = 1;                     #was downloaded
            $mtime   = $res->last_modified;
            unless (utime($mtime, $mtime, $fn)) {
                throw_error("utime($mtime, $mtime, $fn)", $!);
                return ();
            }
        } elsif ($res->code == RC_NOT_MODIFIED) {
            $success = 1;    #was not downloaded, becasue it is cache and unmodified
        } else {
            sleep($self->{"retrieve_wait"});
            $i++;
        }
    }
    unless ($success) {
        throw_error("http request failed", $res->code);
        return ();
    }
    return $fn;
}

#
# _encodeUrl ($url)
#

sub _encodeUrl ($)
{
    my ($url) = @_;
    my $eu = encode_base64($url, "");
    $eu =~ s/\//_/g;
    return $eu;
}

#
# returns current cid (from cid file)
#

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

=pod

=back

=cut

1;

