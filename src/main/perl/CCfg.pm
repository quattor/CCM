# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::CCfg;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use Net::Domain qw(hostname hostdomain);

use CAF::FileReader;

use parent qw(Exporter);
use Readonly;

our @EXPORT    = qw();
our @EXPORT_OK = qw(initCfg getCfgValue);
our $VERSION   = '${project.version}';

=head1 NAME

EDG::WP4::CCM::CCfg

=head1 SYNOPSIS

  init()
    or
  init("/etc/ccm.conf")

  $cache_root = getCfgValue ("cache_root");

=head1 DESCRIPTION

CCfg is used to get configuration parameters. Defualt values for
configuration parameters get overwritten if defined in configuration
file.

=over

=cut

# ------------------------------------------------------

my $ec          = LC::Exception::Context->new->will_store_errors;
my $CONFIG_FN   = "ccm.conf";
my $DEF_EDG_LOC = "/usr";

# Holds the default and all possible keys
Readonly::Hash my %DEFAULT_CFG => {
    "base_url"         => undef,
    "ca_dir"           => undef,
    "ca_file"          => undef,
    "cache_root"       => "/var/lib/ccm",
    "cert_file"        => undef,
    "context"          => undef,
    "dbformat"         => "GDBM_File",
    "debug"            => undef,
    "force"            => undef,
    "get_timeout"      => 30,
    "json_typed"       => 0,
    "keep_old"         => 2,
    "key_file"         => undef,
    "lock_retries"     => 3,
    "lock_wait"        => 30,
    "preprocessor"     => undef,
    "profile"          => undef,
    "profile_failover" => undef,
    "purge_time"       => 86400,
    "retrieve_retries" => 3,
    "retrieve_wait"    => 30,
    "trust"            => undef,
    "world_readable"   => undef,
};

Readonly::Array our @CFG_KEYS => sort(keys(%DEFAULT_CFG));

push(@EXPORT_OK, qw(@CFG_KEYS));

# copy hash to hash ref
my $cfg = {%DEFAULT_CFG};

sub _resolveTags ($)
{
    my ($s) = @_;
    if ($s =~ /\$host/) {
        my $h = hostname();
        unless ($h) {
            throw_error("could not resolve the hostname!");
            return ();
        }
        $h = lc($h);    # use lowercase for host.
        $s =~ s/\$host/$h/g;
    }
    if ($s =~ /\$domain/) {
        my $d = hostdomain();
        unless ($d) {
            throw_error("could not resolve the domainname!");
            return ();
        }
        $s =~ s/\$domain/$d/g;
    }
    return $s;
}

sub _readConfigFile ($)
{
    my ($fn) = @_;

    my $fh = CAF::FileReader->new($fn);
        
    foreach my $line (split ("\n", "$fh")) {
        next if ($line =~ m/^\s*(\#|$)/);
        if ($line =~ m/^\s*(\w+)\s+(\S+)\s*$/) {
            my $var = $1;
            my $val = $2;
            if (exists($DEFAULT_CFG{$var})) {
                if (   $var eq 'profile'
                    or $var eq 'profile_failover'
                    or $var eq 'context')
                {
                    my $s = _resolveTags($val);
                    unless ($s) {
                        throw_error("_resolveTags ($val) for $var", $ec->error);
                        return;
                    }
                    $cfg->{$var} = $s;
                } else {
                    $cfg->{$var} = $val;
                }
            } else {
                throw_error("unknown config variable in $fn: $var (line $line)");
                return;
            }
            next;
        }
        chomp($line);
        throw_error("bad config file $fn syntax: $line");
        return;
    }
    $fh->close();

    return SUCCESS;
}

=item initCfg (;$cfg_file)

Initialise CCfg. if $cfg_file parameter is present, file has to exists,
if it does not exist error is risen. If the parameter is not present
defualt EDG paths are used. If configuration file does not exist in defualt
locations the default values are used.

=cut

sub initCfg
{
    my ($cp) = @_;
    if ($cp) {

        # Accept the configuration be read from pipes (i.e, stdin)
        unless (-f $cp || -p $cp) {
            throw_error("configuration file $cp not found");
            return ();
        }
    } else {
        if (-f "/etc/$CONFIG_FN") {
            $cp = "/etc/$CONFIG_FN";
        } elsif (-f $DEF_EDG_LOC . "/etc/$CONFIG_FN") {
            $cp = $DEF_EDG_LOC . "/etc/$CONFIG_FN";
        } elsif (defined($ENV{"EDG_LOCATION"})
            && -f $ENV{"EDG_LOCATION"} . "/etc/$CONFIG_FN")
        {
            $cp = $ENV{"EDG_LOCATION"} . "/etc/$CONFIG_FN";
        } else {
            #no default configuration file exists
            #default parameters values will be used
            return ();
        }
    }
    unless (_readConfigFile($cp)) {
        throw_error("_readConfigFile($cp)", $ec->error);
        return ();
    }
    return SUCCESS;
}

=item getCfgValue ($key)

returns a value of the configuration parameter identified by $key.

=cut

sub getCfgValue ($)
{
    my ($key) = @_;
    return ($cfg->{$key});
}

# private method to set values, for testing only
sub _setCfgValue
{
    my ($key, $value) = @_;
    if (defined($cfg->{$key})) {
        $cfg->{$key} = $value;
    } else {
        throw_error("Not a valid config key $key");
    }
    # Use the method rather then direct call or simply return value
    return getCfgValue($key);
}

=pod

=back

=cut

1;

