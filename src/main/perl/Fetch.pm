#${PMpre} EDG::WP4::CCM::Fetch${PMpost}

=head1 NAME

EDG::WP4::CCM::Fetch

=head1 SYNOPSIS

  $fetch = EDG::WP4::CCM::Fetch->new({PROFILE_URL => "profile_url or hostname",
                      CONFIG  => "path of config file",
                      FOREIGN => "1/0"});


  $fetch->fetchProfile();

=head1 DESCRIPTION

Module provides Fetch class. This helps in retrieving XML profiles and
from specified URLs. It allows users to retrieve local, as
well as foreign node profiles.

=head1 Functions

=over

=cut

use CAF::Object qw(SUCCESS CHANGED throw_error);
use Carp qw(carp confess);

# only to re-export
use EDG::WP4::CCM::CacheManager qw($GLOBAL_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN
    $DATA_DN);
use EDG::WP4::CCM::Fetch::ProfileCache qw($FETCH_LOCK_FN
    $TABCOMPLETION_FN ComputeChecksum
    $ERROR);

use EDG::WP4::CCM::Fetch::Config qw(NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

use parent qw(Exporter CAF::Reporter EDG::WP4::CCM::Fetch::Config
              EDG::WP4::CCM::Fetch::Download
              EDG::WP4::CCM::Fetch::ProfileCache);

our @EXPORT    = qw();
our @EXPORT_OK = qw($GLOBAL_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN
    $FETCH_LOCK_FN $TABCOMPLETION_FN ComputeChecksum
    NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

my $ec = LC::Exception::Context->new->will_store_errors;

=item new()

  new({PROFILE_URL => "profile_url or hostname",
       CONFIG  => "path of config file",
       FOREIGN => "1/0"});

Creates new Fetch object. Full url of the profile can be provided as
parameter PROFILE_URL, if it is not a url a profile url will be
calculated using 'base_url' config option in /etc/ccm.conf.  Path of
alternative configuration file can be given as CONFIG.

Returns undef in case of error.

=cut

sub new
{

    my ($class, $param) = @_;

    my $self = bless({}, $class);

    my $foreign_profile = ($param->{"FOREIGN"}) ? 1 : 0;

    # remove starting and trailing spaces

    if (!$param->{CONFIG} && $param->{CFGFILE}) {

        # backwards compatability
        $param->{CONFIG} = $param->{CFGFILE};
    }

    # Interpret the config file.
    unless ($self->_config($param->{"CONFIG"}, $param)) {
        $ec->rethrow_error();
        return undef;
    }

    $param->{PROFILE_FORMAT} ||= 'xml';

    $self->{"FOREIGN"} = $foreign_profile;
    if ($param->{DBFORMAT}) {
        $self->{DBFORMAT} = $param->{DBFORMAT};
    }

    $self->setProfileFormat($param->{DBFORMAT});

    # Get correct permissions
    my ($dopts, $fopts, $mask) = $self->GetPermissions($self->{GROUP_READABLE}, $self->{WORLD_READABLE});
    # File permissions opts contains a log instance
    $fopts->{log} = $self; # will be passed as option hash to CAF::File(Writer/Editor)

    $self->{permission} = {
        directory => $dopts,
        file => $fopts,
        mask => $mask,
    };

    return $self;
}

=pod

=item fetchProfile()

fetchProfile  fetches the  profile  from  profile url and keeps it at
configured area.  The  cache  root variable is set as
$fetch_handle{'CACHE_ROOT'} which can further be passed to CacheManager
object and use NVA-API to access Resources and Properties.

If the profile is foreign, then the cache_root configuration is expected
to be just for this foreign host and unexpected behaviour will result
if the cache_root is shared. Only a single (most recent) copy of the
foreign copy will be stored: previous versions will be removed. Foreign
profiles do not use failover URLs: if the primary URL is unavailable,
then the fetch will fail.

Returns undef if it cannot fetch the profile due to a network error,
C<<$EDG::WP4::CCM::Fetch::ProfileCache::ERROR>> in case of other failure,
C<SUCCESS> in case of successful fetch, but no updated profile
and C<CHANGED> in case of successful fetch and
updated profile.


=cut

sub fetchProfile
{

    my ($self) = @_;
    my (%current, %previous);

    if ($self->{FOREIGN_PROFILE} && $self->enableForeignProfile() == $ERROR) {
        $self->error("Unable to enable foreign profiles");
        return $ERROR;
    }

    my $lock = $self->getLocks();

    %previous = $self->previous();

    if (!$self->{FORCE} && "$previous{url}" ne $self->{PROFILE_URL}) {
        $self->debug(
            1,
            "Current URL $self->{PROFILE_URL} is different ",
            "from the previous fetched one $previous{url}. ",
            "Forcing download."
        );
        $self->{FORCE} = 1;
    }

    local $SIG{__WARN__} = \&carp;

    # the global lock is an indicator if CIDs are locked (no pivots
    # allowed)

    my $profile = $self->download("profile");

    my $res;
    if (!defined($profile)) {
        $self->error("Failed to fetch profile $self->{PROFILE_URL}");
    } elsif ("$profile" eq "0") {
        # Have to do string comparison, because profile can be a FileReader or 0
        $self->verbose("fetchProfile: nothing to do, ",
                       "local cache is newer than profile (and no FORCE)");
        $res = SUCCESS;
    } else {
        local $SIG{__DIE__} = sub {
            warn "Cleaning on die";
            $self->_cleanup(\%current, \%previous, 1);
            confess(@_);
        };

        $self->verbose("Downloaded new profile");

        %current = $self->current($profile, %previous);
        if ($self->process_profile("$profile", %current) == $ERROR) {
            $self->error("Failed to process profile for $self->{PROFILE_URL}");
            $self->_cleanup(\%current, \%previous, 1);
            return $ERROR;
        }

        # Make the new profile/CID the latest.cid
        my $new_cid = "$current{cid}";
        # "previous" is all about latest.cid
        $previous{cid}->set_contents($new_cid);

        # Make the new profile/CID the current.cid
        $self->_cleanup(\%current, \%previous);

        # TODO do we need a different/additonal control for foreign tabcompletion
        # (i.e. does tabcompletion on foreign profiles make any sense)
        # Do not check return code, this is not fatal or anything.
        # An error is logged in case of problem
        $self->generate_tabcompletion($new_cid) if $self->{TABCOMPLETION};

        $res = CHANGED;
    }

    return $res;
}

=pod

=back

=cut

1;
