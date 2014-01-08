# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::CCfg;

use strict;
use LC::Exception qw(SUCCESS throw_error);
use Net::Domain qw(hostname hostdomain);

use parent qw(Exporter);

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

my $ec = LC::Exception::Context->new->will_store_errors;
my $CONFIG_FN   = "ccm.conf";
my $DEF_EDG_LOC = "/usr";

my $cfg = {
	      "debug" => undef,
	      "force" => undef,
	      "profile" => undef,
	      "profile_failover" => undef,
	      "context" => undef,
	      "preprocessor" => undef,
	      "cache_root" => "/var/lib/ccm",
	      "get_timeout" => 30,
	      "lock_retries" => 3,
	      "lock_wait" => 30,
	      "retrieve_retries" => 3,
	      "retrieve_wait" => 30,
              "cert_file" => undef,
              "key_file" => undef,
              "ca_file" => undef,
              "ca_dir" => undef,
              "base_url" => undef,
              "world_readable" => undef,
              "dbformat" => "GDBM_File",
              "keep_old" => 2,
              "purge_time" => 86400,
};

sub _resolveTags ($) {
  my ($s) = @_;
  if ($s=~/\$host/) {
    my $h = hostname();
    unless ($h) {
      throw_error ("could not resolve the hostname!");
      return();
    }
    $h = lc($h); # use lowercase for host.
    $s=~s/\$host/$h/g;
  }
  if ($s=~/\$domain/) {
    my $d = hostdomain();
    unless ($d) {
      throw_error ("could not resolve the domainname!");
      return();
    }
    $s=~s/\$domain/$d/g;
}
  return $s;
}

sub _readConfigFile ($) {
    my ($f) = @_;
    unless (open(CONF, "<$f")) {
	throw_error ("can't open config file: $f: $!");
	return ();
    }
    while (<CONF>) {
	if (/^\s*\#/) { next; }
	if (/^\s*$/) { next; }
	if (/^\s*(\w+)\s+(\S+)\s*$/) {
	    my $var = $1;
	    my $val = $2;
	    if ($var eq 'debug') {$cfg->{"debug"}=$val;}
	    elsif ($var eq 'force') {$cfg->{"force"}=$val;}
	    elsif ($var eq 'profile') {
		my $s = _resolveTags ($val);
		unless ($s) {
		    throw_error ("_resolveTags ($val)", $ec->error);
		    return ();
		}
		$cfg->{"profile"}=$s;
	    }
	    elsif ($var eq 'profile_failover') {
		my $s = _resolveTags ($val);
		unless ($s) {
		    throw_error ("_resolveTags ($val)", $ec->error);
		    return ();
		}
		$cfg->{"profile_failover"}=$s;
	    }
	    elsif ($var eq 'context') {
		my $s = _resolveTags ($val);
		unless ($s) {
		    throw_error ("_resolveTags ($val)", $ec->error);
		    return ();
		}
		$cfg->{"context"}=$s;
	    }
	    elsif ($var eq 'cache_root') {$cfg->{"cache_root"}=$val;}
	    elsif ($var eq 'get_timeout') {$cfg->{"get_timeout"}=$val;}
	    elsif ($var eq 'lock_retries') {$cfg->{"lock_retries"}=$val;}
	    elsif ($var eq 'lock_wait') {$cfg->{"lock_wait"}=$val;}
	    elsif ($var eq 'retrieve_retries') {$cfg->{"retrieve_retries"}=$val;}
	    elsif ($var eq 'retrieve_wait') {$cfg->{"retrieve_wait"}=$val;}
	    elsif ($var eq 'preprocessor') {$cfg->{"preprocessor"}=$val;}
            elsif ($var eq 'cert_file') {$cfg->{"cert_file"}=$val;}
            elsif ($var eq 'key_file') {$cfg->{"key_file"}=$val;}
            elsif ($var eq 'ca_file') {$cfg->{"ca_file"}=$val;}
            elsif ($var eq 'ca_dir') {$cfg->{"ca_dir"}=$val;}
            elsif ($var eq 'base_url') {$cfg->{"base_url"}=$val;}
            elsif ($var eq 'world_readable') {$cfg->{"world_readable"}=$val;}
            elsif ($var eq 'dbformat') {$cfg->{"dbformat"}=$val;}
            elsif ($var eq 'trust') {$cfg->{"trust"}=$val;}
            elsif ($var eq 'keep_old') {$cfg->{"keep_old"}=$val;}
            elsif ($var eq 'purge_time') {$cfg->{"purge_time"}=$val;}
	    else { throw_error("unknown config variable: $var"); }
	    next;
	}
	chomp;
	throw_error ("bad config file syntax: $_");
    }
    close(CONF);
    return SUCCESS;
}

=item initCfg (;$cfg_file)

Initialise CCfg. if $cfg_file parameter is present, file has to exists,
if it does not exist error is risen. If the parameter is not present
defualt EDG paths are used. If configuration file does not exist in defualt
locations the default values are used.

=cut

sub initCfg {
  my ($cp) = @_;
  if ($cp) {
      # Accept the configuration be read from pipes (i.e, stdin)
    unless (-f $cp || -p $cp) {
      throw_error ("configuration file not found");
      return();
    }
  } else {
    if (-f "/etc/$CONFIG_FN") {
      $cp = "/etc/$CONFIG_FN";
    } elsif (-f $DEF_EDG_LOC."/etc/$CONFIG_FN") {
      $cp = $DEF_EDG_LOC."/etc/$CONFIG_FN";
    } elsif (defined($ENV{"EDG_LOCATION"})
      && -f $ENV{"EDG_LOCATION"}."/etc/$CONFIG_FN") {
      $cp = $ENV{"EDG_LOCATION"}."/etc/$CONFIG_FN";
    } else {
      #no default configuration file exists
      #default parameters values will be used
      return();
    }
  }
  unless (_readConfigFile($cp)) {
    throw_error ("_readConfigFile($cp)", $ec->error);
    return ();
  }
  return SUCCESS;
}

=item getCfgValue ($key)

returns a value of the configuration parameter identified by $key.

=cut

sub getCfgValue ($) {
  my ($key) = @_;
  return ($cfg->{$key});
}

1;

__END__

=back

=head1 AUTHOR

Piotr Poznanski <Piotr.Poznanski@cern.ch>

=head1 VERSION

${project.version}

=cut
