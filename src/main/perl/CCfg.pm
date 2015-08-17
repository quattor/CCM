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
our @EXPORT_OK = qw(initCfg getCfgValue setCfgValue resetCfg);
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
Readonly my $DEF_EDG_LOC => "/usr";
Readonly our $CONFIG_FN   => "/etc/ccm.conf";

# Ordered list of all options in config file
# semi-AppConfig style (NAME=option.suffix)
# Based 15.4 DEFAULT_CFG from CCfg.pm (keys and default values)
# and order and help of ccm-fetch (not all ccm-fetch options are here)
Readonly::Array our @CONFIG_OPTIONS => (
    {
        option => 'profile',
        suffix => '|p=s',
        HELP => 'URL of profile to fetch',
    },

    {
        option => 'profile_failover',
        suffix => '=s',
        HELP => 'URL of profile to fetch when --profile is not available, can be comma separated',
    },

    {
        option => 'context',
        suffix => '|c=s',
        HELP    => 'URL of context to fetch',
    },

    {
        option => 'preprocessor',
        suffix => '=s',
        HELP    => 'Path of executable to be used to preprocess a profile with a context',
    },

    {
        option => 'cache_root',
        suffix => '=s',
        DEFAULT => '/var/lib/ccm',
        HELP    => 'Basepath for the configuration cache',
    },

    {
        option => 'get_timeout',
        suffix => '=i',
        DEFAULT => 30,
        HELP    => 'Timeout in seconds for HTTP GET operation',
    },

    {
        # TODO: ccm-fetch has default 1
        option => 'world_readable',
        suffix => '=i',
        HELP    => 'World readable profile flag 1/0',
    },

    {
        option => 'force',
        suffix => '|f',
        HELP    => 'Fetch regardless of modification times',
    },

    {
        option => 'dbformat',
        suffix => '=s',
        DEFAULT => 'GDBM_File',
        HELP    => 'Format to use for storing profile',
    },

    {
        option => 'retrieve_retries',
        suffix => '=i',
        DEFAULT => 3,
        HELP    => 'Number of times fetch will attempt to retrieve a profile',
    },

    {
        option => 'lock_retries',
        suffix => '=i',
        DEFAULT => 3,
        HELP    => 'Number of times fetch will attempt to get the fetch lock',
    },

    {
        option => 'retrieve_wait',
        suffix => '=i',
        DEFAULT => 30,
        HELP    => 'Number of seconds that fetch will wait between retrieve attempts',
    },

    {
        option => 'lock_wait',
        suffix => '=i',
        DEFAULT => 30,
        HELP    =>  'Number of seconds that fetch will wait between lock attempts',
    },

    {
        option => 'key_file',
        suffix => '=s',
        HELP    => 'Absolute file name for key file to use with HTTPS.',
    },

    {
        option => 'cert_file',
        suffix => '=s',
        HELP    => 'Absolute file name for certificate file to use with HTTPS.',
    },

    {
        option => 'ca_file',
        suffix => '=s',
        HELP    => 'File containing a bundle of trusted CA certificates for use with HTTPS.',
    },

    {
        option => 'ca_dir',
        suffix => '=s',
        HELP   => 'Directory containing trusted CA certificates for use with HTTPS',
    },

    {
        option => 'trust',
        suffix => '=s',
        HELP   => 'Kerberos principal to trust if using encrypted profiles',
    },

    {
        option => 'keep_old',
        suffix => '=i',
        DEFAULT => 2,
        HELP   => 'Number of old profiles to keep before purging',
    },

    {
        option => 'purge_time',
        suffix => '=i',
        DEFAULT => 86400,
        HELP   => 'Number of seconds before purging inactive profiles',
    },

    {
        option => 'json_typed',
        DEFAULT => 0,
        HELP => 'Extract typed data from JSON profiles',
    },

    {
        option => 'debug',
        suffix => '|d=i',
        HELP => 'Turn on debugging messages',
    },

    {
        option => 'base_url',
        suffix => '=s',
        HELP => 'Base url to use when the profile is relative',
    },

    {
        option => 'tabcompletion',
        DEFAULT => 0,
        HELP => 'Create the tabcompletion file (during profile fetch)',
    },
);

Readonly::Array our @CFG_KEYS => sort map {$_->{option}} @CONFIG_OPTIONS;

push(@EXPORT_OK, qw(@CONFIG_OPTIONS $CONFIG_FN @CFG_KEYS));

# Holds the default and all possible keys
Readonly::Hash my %DEFAULT_CFG =>
    map {$_->{option} => $_->{DEFAULT}} @CONFIG_OPTIONS;


# copy hash to hash ref
# TODO this is a global config instance,
# there is no support for multiple configfiles
my $cfg = {%DEFAULT_CFG};


# Hash ref that hold configuration files that will be forced,
# even when re-reading the config file
my $force_cfg = {};

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

# This format is "<key> <value>" and is readable by AppConfig
# But lots of AppConfig file format features
# are not supported with this reader.
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
                if (exists $force_cfg->{$var}) {
                    # Force the values
                    $cfg->{$var} = $force_cfg->{$var};
                } elsif (   $var eq 'profile'
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
        if (-f $CONFIG_FN) {
            $cp = $CONFIG_FN;
        } elsif (-f $DEF_EDG_LOC . $CONFIG_FN) {
            $cp = $DEF_EDG_LOC . $CONFIG_FN;
        } elsif (defined($ENV{"EDG_LOCATION"})
            && -f $ENV{"EDG_LOCATION"} . $CONFIG_FN)
        {
            $cp = $ENV{"EDG_LOCATION"} . $CONFIG_FN;
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
# throws an error on unknown key
sub _setCfgValue
{
    my ($key, $value) = @_;
    if (exists($cfg->{$key})) {
        $cfg->{$key} = $value;
    } else {
        throw_error("Not a valid config key $key");
    }
    # Use the method rather then direct call or simply return value
    return getCfgValue($key);
}

=item setCfgValue ($key, $value, $force)

Set the configuration option C<$key> to C<$value>.
If force is set, the option and value are also added
to the C<force_cfg> hashref, making it protected against
rereading of the config file.

=cut

sub setCfgValue
{
    my ($key, $value, $force) = @_;
    my $newvalue = _setCfgValue($key, $value);

    # _setCfgValue throws error on unknown key

    if ($force) {
        $force_cfg->{$key} = $value;
    }

    # for unittesting
    return $newvalue;
}

=item resetCfg

reset the configuration hash and empty the force
hashref.

=cut

sub resetCfg
{
    $cfg = {%DEFAULT_CFG};
    $force_cfg = {};
}

=pod

=back

=cut

1;
