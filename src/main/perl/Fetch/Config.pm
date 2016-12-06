#${PMpre} EDG::WP4::CCM::Fetch::Config${PMpost}

=head1 NAME

EDG::WP4::CCM::Fetch::Config

=head1 DESCRIPTION

Module provides methods to handle any configuration options set in either
CCM config and/or the commandline

=head1 Functions

=over

=cut

use EDG::WP4::CCM::CCfg qw(initCfg getCfgValue @CFG_KEYS);
use LC::Exception qw(SUCCESS throw_error);

use parent qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

use constant NOQUATTOR          => "/etc/noquattor";
use constant NOQUATTOR_EXITCODE => 3;
use constant NOQUATTOR_FORCE    => "force-quattor";

my $ec = LC::Exception::Context->new->will_store_errors;

sub _config
{
    my ($self, $cfg, $param) = @_;

    unless (initCfg($cfg)) {
        $ec->rethrow_error();
        return ();
    }

    $self->{_CCFG} = $cfg;

    my @keys = qw(tmp_dir);
    push(@keys, @CFG_KEYS);
    foreach my $key (@keys) {
        # do not override any predefined uppercase attributes
        if (! defined($self->{uc($key)})) {
            $self->{uc($key)} = defined($param->{uc($key)}) ? $param->{uc($key)} : getCfgValue($key);
        };
    }

    $self->setProfileURL(($param->{PROFILE_URL} || $param->{PROFILE} || getCfgValue('profile')));
    if (getCfgValue('trust')) {
        $self->{"TRUST"} = [split(/\s*,\s*/, getCfgValue('trust'))];
    } else {
        $self->{"TRUST"} = [];
    }

    $self->{CACHE_ROOT} =~ m{^([-.:\w/]+)$}
        or die "Weird root for cache: $self->{CACHE_ROOT} on profile $self->{PROFILE_URL}";
    $self->{CACHE_ROOT} = $1;
    if ($self->{TMP_DIR}) {
        $self->{TMP_DIR} =~ m{^([-.\w/:]*)$}
            or die "Weird temp directory: $self->{TMP_DIR} on profile $self->{PROFILE_URL}";
        $self->{TMP_DIR} = $1;

    }
    $self->{DBFORMAT} =~ m{^([a-zA-Z]\w+)(::[a-zA-Z]\w+)*$}
        or die "Weird cache format $self->{DBFORMAT} for profile $self->{PROFILE_URL}";
    $self->{DBFORMAT} = $1;
    map(defined($_) && chomp, values(%$self));

    return SUCCESS;
}

#
# Override configuration parameters
#

# Set Cache Root directory
sub setCacheRoot
{
    my ($self, $val) = @_;
    throw_error("directory does not exist: $val") unless (-d $val);
    $self->{"CACHE_ROOT"} = $val;
    return SUCCESS;
}

# Set CA directory
sub setCADir
{
    my ($self, $val) = @_;
    throw_error("CA directory does not exist: $val") unless (-d $val);
    $self->{CA_DIR} = $val;
    return SUCCESS;
}

# Set CA files
sub setCAFile
{
    my ($self, $val) = @_;
    throw_error("CA file does not exist: $val") unless (-r $val);
    $self->{CA_FILE} = $val;
    return SUCCESS;
}

# Set Key files path
sub setKeyFile
{
    my ($self, $val) = @_;
    throw_error("Key file does not exist: $val") unless (-r $val);
    $self->{KEY_FILE} = $val;
    return SUCCESS;
}

sub setCertFile
{
    my ($self, $val) = @_;
    throw_error("cert_file does not exist: $val") unless (-r $val);
    $self->{CERT_FILE} = $val;
    return SUCCESS;
}

sub setConfig
{
    my ($self, $val) = @_;
    $self->_config($val);
}

sub setProfileURL
{
    my ($self, $prof) = @_;
    chomp($prof);
    my $base_url = $self->{"BASE_URL"};
    $self->debug(5, "base_url is not defined in configuration")
        unless (defined $base_url);
    if ($prof =~ m{^(?:http|https|ssh|file)://}) {
        $self->{"PROFILE_URL"} = $prof;
    } else {
        $self->{"PROFILE_URL"} =
            (defined $base_url)
            ? $base_url . "/profile_" . $prof . ".xml"
            : "profile_" . $prof . ".xml";
    }
    $self->{PROFILE_URL} =~ m{^((?:http|https|ssh|file)://[-/.\?\w:=%&]+)$}
        or die "Invalid profile url $self->{PROFILE_URL}";
    $self->{PROFILE_URL} = $1;
    $self->debug(5, "URL is " . $self->{"PROFILE_URL"});
    return SUCCESS;
}

sub setGroupReadable
{
    my ($self, $val) = @_;
    # Report this, but do not fail
    $self->warn("Group readable option should be valid groupname: could not resolve $val")
        unless (defined(getgrnam($val)));
    # Setting it anyway, invalid groups are handled properly
    $self->{"GROUP_READABLE"} = $val;
    return SUCCESS;
}

sub setWorldReadable
{
    my ($self, $val) = @_;
    throw_error("World readable option should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{"WORLD_READABLE"} = $val;
    return SUCCESS;
}

=item setNotificationTime()

Define notification time, if profile modification time is greater than
notification time then only the profile will be downloaded

=cut

sub setNotificationTime
{
    my ($self, $val) = @_;
    throw_error("Notification time should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{NOTIFICATION_TIME} = $val;
    return SUCCESS;
}

=item setTimeout()

Define timeout after which profile fetch will be terminated.

=cut

sub setTimeout
{
    my ($self, $val) = @_;
    throw_error("Timeout should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{GET_TIMEOUT} = $val;
    return SUCCESS;
}

sub setForce
{
    my ($self, $val) = @_;
    throw_error("Force should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{"FORCE"} = $val;
    return SUCCESS;
}

=item setProfileFailover()

Define failover profile url

=cut

sub setProfileFailover
{
    my ($self, $val) = @_;
    $self->{"PROFILE_FAILOVER"} = $val;
    return SUCCESS;
}

sub setPrincipal
{
    my ($self, $val) = @_;
    throw_error("Invalid characters in principal: $val")
        unless ($val =~ m/^[\w.\-\/@]+$/);
    $self->{PRINCIPAL} = $val;
    return SUCCESS;
}

sub setKeytab
{
    my ($self, $val) = @_;
    throw_error("Keytab $val not readable") unless (-r $val);
    $self->{KEYTAB} = $val;
    return SUCCESS;
}

sub getCacheRoot
{
    my ($self) = @_;
    return $self->{"CACHE_ROOT"};
}

sub getProfileURL
{
    my ($self) = @_;
    return $self->{"PROFILE_URL"};
}

sub getForce
{
    my ($self) = @_;
    return $self->{"FORCE"};
}

=pod

=back

=cut

1;
