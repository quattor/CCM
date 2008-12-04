# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}
package      EDG::WP4::CCM::Fetch;

=head1 NAME

EDG::WP4::CCM::Fetch

=head1 SYNOPSIS

  $fetch = EDG::WP4::CCM::Fetch->new({PROFILE => "profile_url or hostname",
				      CONFIG  => "path of config file",
				      FOREIGN => "1/0"});

	
  $fetch->setDebug(1);
  $fetch->fetchProfile();

=head1 DESCRIPTION

  Module  provides  Fetch class. This helps in retrieving XML profiles and 
  contexts from specified URLs. It allows users to retrieve local, as well 
  as foreign node profiles.

=over

=head1 Functions

=cut

use strict;
use Getopt::Long;
use EDG::WP4::CCM::CCfg;
use Fcntl ':flock';
use MIME::Base64;
use LWP::UserAgent;
use XML::Parser;
use Compress::Zlib;
use Digest::MD5 qw(md5_hex);
use GDBM_File;
use Sys::Hostname;
use File::Basename;
use LC::Exception qw(SUCCESS throw_error);
use File::Temp qw /tempfile tempdir/;
use File::Path;
use Encode qw(encode_utf8);

use constant MAXPROFILECOUNTER => 9999 ;
use constant ERROR => -1 ;
BEGIN{
    use      Exporter;
    use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

    @ISA       = qw(Exporter);
    @EXPORT    = qw();           
    @EXPORT_OK = qw($GLOBAL_LOCK_FN $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN);
}



my $ec = LC::Exception::Context->new->will_store_errors;

# Global Variables
my $debug ;
my $context_time = 0;
my $get_timeout  = 30;		# Default timeout
my $ca_dir;
my $ca_file;
my $key_file;
my $cert_file;
my $notification_time = 0;

my $profile_ntime     = undef;
my $context_ntime     = undef;

my $GLOBAL_LOCK_FN = "global.lock";
my $FETCH_LOCK_FN  = "fetch.lock";

=item new()

  new({PROFILE => "profile_url or hostname", 
       CONFIG  => "path of config file", 
       FOREIGN => "1/0"});

  Creates new Fetch object. Full url of the profile can be provided as 
  parameter  PROFILE,  if  it  is  not  a  url  a  profile url will be 
  calculated using 'base_url' config option in /etc/ccm.conf.  Path of 
  alternative configuration file can be given as CONFIG. 

  Returns undef in case of error.

=cut

sub new {

    my ($class, $param) = @_;
    my $self = {};

    my $foreign_profile = ($param->{"FOREIGN"}) ? 1 : 0;

    # remove starting and trailing spaces
    $param->{"PROFILE"} = trim($param->{"PROFILE"}) if $param->{"PROFILE"};

    bless ($self, $class);

    # Interpret the config file.
    unless ($self->_config($param->{"CONFIG"}))
    {
	$ec->rethrow_error();
	return undef;
    }

    # Set the profile URL if user is specifying it
    if ($param->{"PROFILE"})
    {
	$self->setProfileURL($param->{"PROFILE"});
    }

    $self->{"FOREIGN"} = $foreign_profile;
    $self->{"HOST"}    = $self->getHostName;

    # Return the object
    return $self;
}

sub _config($){

    my $self = shift;
    unless (EDG::WP4::CCM::CCfg::initCfg(shift)){
	$ec->rethrow_error();
	return();
    }

    # Global Variables
    $debug                      = EDG::WP4::CCM::CCfg::getCfgValue('debug');
    $get_timeout                = EDG::WP4::CCM::CCfg::getCfgValue('get_timeout');
    $cert_file                  = EDG::WP4::CCM::CCfg::getCfgValue('cert_file');
    $key_file                   = EDG::WP4::CCM::CCfg::getCfgValue('key_file');
    $ca_file                    = EDG::WP4::CCM::CCfg::getCfgValue('ca_file');
    $ca_dir                     = EDG::WP4::CCM::CCfg::getCfgValue('ca_dir');


    # Local Variables to the object
    $self->{"FORCE"}            = EDG::WP4::CCM::CCfg::getCfgValue('force');
    $self->{"BASE_URL"}         = EDG::WP4::CCM::CCfg::getCfgValue('base_url');
    $self->{"PROFILE_URL"}      = EDG::WP4::CCM::CCfg::getCfgValue('profile');
    $self->{"PROFILE_FAILOVER"} = EDG::WP4::CCM::CCfg::getCfgValue('profile_failover');
    $self->{"CONTEXT_URL"}      = EDG::WP4::CCM::CCfg::getCfgValue('context');
    $self->{"CACHE_ROOT"}       = EDG::WP4::CCM::CCfg::getCfgValue('cache_root');
    $self->{"LOCK_RETRIES"}     = EDG::WP4::CCM::CCfg::getCfgValue('lock_retries');
    $self->{"LOCK_WAIT"}        = EDG::WP4::CCM::CCfg::getCfgValue('lock_wait');
    $self->{"RETRIEVE_RETRIES"} = EDG::WP4::CCM::CCfg::getCfgValue('retrieve_retries');
    $self->{"RETRIEVE_WAIT"}    = EDG::WP4::CCM::CCfg::getCfgValue('retrieve_wait');
    $self->{"PREPROCESSOR"}     = EDG::WP4::CCM::CCfg::getCfgValue('preprocessor');
    $self->{"WORLD_READABLE"}   = EDG::WP4::CCM::CCfg::getCfgValue('world_readable');
    $self->{"TMP_DIR"}          = EDG::WP4::CCM::CCfg::getCfgValue('tmp_dir');

    return SUCCESS;
}

=item fetchProfile()

  fetchProfile  fetches the  profile  from  profile  url and keeps it at 
  configured area. If  the  profile is  FOREIGN then a temporary area is 
  created and profile is kept there. The  cache  root variable is set as 
  $fetch_handle{'CACHE_ROOT'} which can further be passed to CacheManager 
  object and use NVA-API to access Resources and Properties.

  Returns -1 and error_msg on failure

=cut

sub fetchProfile {

    my $class = shift;
    my $errno; 
    my $errmsg;

    # Whether profile to be fetched is foreign
    my $foreign_profile       = $class->{"FOREIGN"};
    my $force                 = $class->{"FORCE"};
    my $profile_url           = $class->{"PROFILE_URL"};
    my $profile_failover      = $class->{"PROFILE_FAILOVER"};
    my $context_url           = $class->{"CONTEXT_URL"};
    my $lock_retries          = $class->{"LOCK_RETRIES"};
    my $lock_wait             = $class->{"LOCK_WAIT"};
    my $retrieve_retries      = $class->{"RETRIEVE_RETRIES"};
    my $retrieve_wait         = $class->{"RETRIEVE_WAIT"};
    my $preprocessor          = $class->{"PREPROCESSOR"};
    my $world_readable        = $class->{"WORLD_READABLE"};

    # Setup https environment if necessary.
    $ENV{'HTTPS_CERT_FILE'}   = $cert_file if (defined($cert_file));
    $ENV{'HTTPS_KEY_FILE'}    = $key_file if (defined($key_file));
    $ENV{'HTTPS_CA_FILE'}     = $ca_file if (defined($ca_file));
    $ENV{'HTTPS_CA_DIR'}      = $ca_dir if (defined($ca_dir));

    if ($foreign_profile)
    {
	($errno, $errmsg) = $class->enableForeignProfile();
	return (ERROR, $errmsg) if ($errno == ERROR);
    }

    # Get the cache root (It changes if it is foreign profile)
    my $cache_root            = $class->{"CACHE_ROOT"};

    # test for presence of lock files
    #my $global_lock = ($foreign_profile) ? "$old_cache_root/global.lock" : "$cache_root/global.lock";
    my $global_lock = "$cache_root/$GLOBAL_LOCK_FN";
    return(ERROR, "lock file absent or non-writable: $global_lock") unless (-w $global_lock);
    my $fetch_lock  = "$cache_root/$FETCH_LOCK_FN";
    return(ERROR, "lock file absent or non-writable: $fetch_lock") unless (-w $fetch_lock);

    # obtain single-instance-of-fetch lock
    my $fetch_lock_fh;
    my $tries = 1;

    while (not $fetch_lock_fh = RequestLock($fetch_lock)) {
	Quit("can't get lock: $fetch_lock") if ($tries++ > $lock_retries);
	sleep($lock_wait);
    }

    # core algorithm, part 1: download new versions of profile/context

    # first, profile
    my $profile_cache = "$cache_root/data/" . EncodeURL($profile_url);
    my $profile_ctime = (-r $profile_cache ? (stat($profile_cache))[9] : 0);
    my $gotp = undef;
    # if we got a notification time, try for a while to only get a profile
    # that's at least as recent
    if (defined $profile_ntime and $profile_ntime > $profile_ctime) {
	$tries = 0;
	while ($tries++ < $retrieve_retries) {
	    $gotp = $class->Retrieve($profile_url, $profile_cache,
				     $profile_ntime);
	    last if ($gotp == 1 || $gotp ==3 || $gotp ==0);
	    Debug("$profile_url: try $tries out of $retrieve_retries: sleeping for $retrieve_wait seconds ...");
	    sleep($retrieve_wait);
	}
	if ((($gotp ==2 || $gotp ==3) && defined $profile_failover)
	    && ! $foreign_profile) {
	    Warn("primary URL failed, trying failover: ".$profile_failover);
	    # primary URL failed.
	    # try now failover URL
	    $tries = 0;
	    while ($tries++ < $retrieve_retries) {
		$gotp = $class->Retrieve($profile_failover, $profile_cache,
					 $profile_ntime);
		last if ($gotp == 1 || $gotp == 3 || $gotp == 0);
		Debug("$profile_url: $tries out of $retrieve_retries: "
		      . "sleeping for $retrieve_wait seconds ...");
		sleep($retrieve_wait);
	    }
	}
    }
    # otherwise, just rely on modification time of cached profile
    # and retry in case of read timeouts
    if (((!defined($gotp)) || ($gotp != 1))              # didn't download yet,
    	&& !                   # (and we didn't get a notify <= cache time)
    	(defined $profile_ntime && $profile_ntime <= $profile_ctime)) {
	$tries = 0;
	while ($tries++ < $retrieve_retries) {
	    $gotp = $class->Retrieve($profile_url, $profile_cache,
				     $profile_ntime);
	    last if ($gotp == 1 || $gotp ==3 || $gotp ==0 );
	    Debug("$profile_url: $tries out of $retrieve_retries: sleeping for $retrieve_wait seconds ...");
	    sleep($retrieve_wait);
	}
	if ((($gotp ==2 || $gotp ==3) && defined $profile_failover)
	    && ! $foreign_profile) {
	    # primary URL failed.
	    # try now failover URL
	    Warn("primary URL failed, trying failover: ".$profile_failover);
	    $tries = 0;
	    while ($tries++ < $retrieve_retries) {
		last if (($gotp = $class->Retrieve($profile_failover,
						   $profile_cache)) != 2);
		Debug("$profile_url: $tries out of $retrieve_retries: sleeping for $retrieve_wait seconds ...");
		sleep($retrieve_wait);
	    }
	}
    }
    if ($gotp != 1 && $gotp != 0 ) {
	my $failed_urls = (defined $profile_failover && ! $foreign_profile)?
	    "<$profile_url> or <$profile_failover>": "<$profile_url>";
	return(ERROR, "can't get: $failed_urls");
    }

    # second, context
    my $gotc = undef;
    my $context_cache = undef;
    my $context_ctime = undef;
    if (defined $context_url) {
	$context_cache = "$cache_root/data/" . EncodeURL($context_url);
	$context_ctime = (-r $context_cache ? (stat($context_cache))[9] : 0);
	# if we got a notification time, try for a while to only get a context
	# that's at least as recent
	if (defined $context_ntime and $context_ntime > $context_ctime) {
	    $tries = 0;
	    while ($tries++ < $retrieve_retries) {
		last if (($gotc = $class->Retrieve($context_url, $context_cache,
						   $context_ntime)) == 1);
		sleep($retrieve_wait);
	    }
	}
	# otherwise, just rely on modification time of cached context
	# and retry in case of read timeouts
	if (($gotc != 1)              # didn't download yet,
        	and not                   # (and we didn't get a notify <= cache time)
        	(defined $context_ntime and $context_ntime <= $context_ctime)) {
	    $tries = 0;
	    while ($tries++ < $retrieve_retries) {
		last if (($gotc = $class->Retrieve($context_url, $context_cache)) != 2);
	    }
	}
	return(ERROR, "can't get: <$context_url>") if ($gotc != 1);
    }

    # core algorithm, part 2: update configuration state

    # get latest.cid & current.cid values
    my $latest_cid = "$cache_root/latest.cid";
    my $latest = (-f $latest_cid ? FileToString($latest_cid) : undef);

    # if we have a latest config cached, retrieve its profile & context URLs
    my $latest_dir = (defined $latest ? "$cache_root/profile.$latest" : undef);
    my $latest_profile_url =
    	(defined $latest_dir and -f "$latest_dir/profile.url" ?
	 FileToString("$latest_dir/profile.url") : undef);
    my $latest_context_url =
    	(defined $latest_dir and -f "$latest_dir/context.url" ?
	 FileToString("$latest_dir/context.url") : undef);
    # and the XML
    my $latest_profile_xml =
    	(defined $latest_dir and -f "$latest_dir/profile.xml" ?
	 "$latest_dir/profile.xml" : undef);

    # if we downloaded a profile or a context -- or we didn't, but have been
    # given different URLs from those in the latest config (in which case their
    # content must already be cached in the data dir) -- call the preprocessor
    # prior to making a new config
    my $tmp_profile_xml = "$cache_root/tmp/profile.xml";
    if ($gotp || $gotc
    	|| (defined $latest_profile_url &&
	    $profile_url ne $latest_profile_url)
    	|| (defined $latest_context_url &&
	    $context_url ne $latest_context_url)) {
	# preprocess (if we can)
	if (defined $context_url and defined $preprocessor) {
	    PreProcess($preprocessor, $profile_cache, $context_cache,
		       $tmp_profile_xml);
	} else {
	    system "cp -p $profile_cache $tmp_profile_xml";
	}

	# is the resulting XML different from what we had before?
	Debug("Main: comparing $tmp_profile_xml, $latest_profile_xml");
	if (!defined $latest_profile_xml
        	or FilesDiffer($tmp_profile_xml, $latest_profile_xml)
        	or $force) {
	    # yes: parse & interpret new XML
	    Debug("Main: parsing & interpreting $tmp_profile_xml");
	    my $profile = Interpret(Parse($tmp_profile_xml));

	    # create new profile directory in tmp space
	    my $profdir = "$cache_root/tmp/profile.new";
	    system "rm -rf $profdir"; # in case an earlier run got aborted...
	    if ($world_readable) {
		mkdir($profdir, 0755)
		    or return(ERROR, "can't make profile dir: $profdir: $!");
	    } else {
		mkdir($profdir, 0700)
		    or return(ERROR, "can't make profile dir: $profdir: $!");
	    }
	    rename($tmp_profile_xml, "$profdir/profile.xml")
		or return(ERROR, "can't move $tmp_profile_xml to $profdir/profile.xml: $!");
	    ($errno, $errmsg) = StringToFile($profile_url,
					     "$profdir/profile.url");
	    return (ERROR, $errmsg) if ($errno == ERROR);
	    if (defined $context_url) {
		($errno, $errmsg) = StringToFile($context_url,
						 "$profdir/context.url");
		return (ERROR, $errmsg) if ($errno == ERROR);
	    }
	    ($errno, $errmsg) = MakeDatabase($profile,
					     "$profdir/path2eid.db",
					     "$profdir/eid2data.db");
	    return (ERROR, $errmsg) if ($errno == ERROR);
        
	    # increment $latest and move profile dir to final location
	    $latest = (defined $latest ? $latest + 1 : 0);
	    # restart from 0 if $latest > max profile counter
	    $latest = 0 if ($latest > MAXPROFILECOUNTER);
	    # don't keep multiple copies of foreign profiles
	    $latest = 0 if ($foreign_profile);
	    system "rm -rf $cache_root/profile.$latest" if ($foreign_profile);
	    rename($profdir, "$cache_root/profile.$latest")
		or return(ERROR, "can't move $profdir to $cache_root/profile.$latest: $!");
	    StringToFile($latest, $latest_cid);
	    ($errno, $errmsg) = StringToFile($latest, $latest_cid);
	    return (ERROR, $errmsg) if ($errno == ERROR);
        
	    # update current.cid if not globally locked
	    if (my $lock = RequestLock($global_lock)) {
		if (FileToString($global_lock) eq 'no') {
		    Debug('Main: global.lock is "no"');
		    my $current_cid = "$cache_root/current.cid";
		    my $tmp_current_cid = "$cache_root/tmp/current.cid";
		    StringToFile($latest, $tmp_current_cid);
		    rename($tmp_current_cid, $current_cid);
		}
		ReleaseLock($lock, $global_lock);
	    }
	}
    }

    ReleaseLock($fetch_lock_fh, $fetch_lock);

    return(SUCCESS);

}


######################################################################################
# Supporting functions
######################################################################################



#######################################################################
sub RequestLock ($) {
    #######################################################################

    # Try to get a flock(); return filehandle if successful.

    my $lock = shift;
    local *FH;
    open(FH, "+<$lock") or return(0, "can't open lock file: $lock: $!");
    Debug("RequestLock: trying for lock: $lock");
    if (flock(FH, LOCK_EX | LOCK_NB)) {
        Debug("RequestLock: lock obtained: $lock");
        return *FH;
    } else {
        Debug("RequestLock: lock refused: $lock");
        return 0;
    }
}

#######################################################################
sub ReleaseLock ($$) {
    #######################################################################

    # Release flock() on given filehandle (filename for diagnostics).

    my $fh = shift;
    my $lock = shift;
    Debug("ReleaseLock: releasing: $lock");
    flock($fh, LOCK_UN) or Warn("couldn't release lock: $lock: $!");
    close($fh);
}

#######################################################################
sub Quit (;$) {
    #######################################################################


    if (defined($_[0])) {
	my $msg = $_[0];
	my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
	$msg = sprintf("%04d/%02d/%02d-%02d:%02d:%02d [ERROR] %s",
		       $year+1900, $mon+1, $mday, $hour, $min, $sec,$msg);
        print STDERR $msg . "\n";
        exit(1);
    } else {
        exit(0);
    }
}

#######################################################################
sub Warn ($) {
    #######################################################################

    my $msg = $_[0];
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    $msg = sprintf("%04d/%02d/%02d-%02d:%02d:%02d [WARN] %s",
                   $year+1900, $mon+1, $mday, $hour, $min, $sec,$msg);
    print STDERR $msg . "\n";
}

#######################################################################
sub Debug ($) {
    #######################################################################
 
    my $msg = shift;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    $msg = sprintf("%04d/%02d/%02d-%02d:%02d:%02d [DEBUG] %s",
                   $year+1900, $mon+1, $mday, $hour, $min, $sec,$msg);
    print $msg . "\n"if (defined($debug) && $debug != "0");
}

#######################################################################
sub Base64Encode ($) {
    #######################################################################

    # Uses MIME::Base64 -- with no breaking result into lines.    
    # Always returns a value.

    return encode_base64(shift, '');
}

#######################################################################
sub Base64Decode ($) {
    #######################################################################

    # Need to catch warnings from MIME::Base64's decode function.
    # Returns undef on failure.

    my $data = shift;
    my $msg = undef;
    $SIG{__WARN__} = sub { $msg = $_[0]; };
    my $plain = decode_base64($data);
    $SIG{__WARN__} = 'DEFAULT';
    if ($msg) {
        $msg =~ s/ at.*line [0-9]*.$//;
        chomp($msg);
        Warn('base64 decode failed on "'
             . substr($data, 0, 10)
             . "\"...: $msg");
        return undef;
    } else {
        return $plain;
    }
}

#######################################################################
sub Gunzip ($) {
    #######################################################################

    # Returns undef on failure.

    my $data = shift;
    my $plain = Compress::Zlib::memGunzip($data);
    if (not defined $plain) {
        Warn('gunzip failed on "' . substr($data, 0, 10) . '"...');
        return undef;
    } else {
        return $plain;
    }
}

#######################################################################
sub Base64UscoreEncode ($) {
    #######################################################################

    # base64, then with "/" -> "_"

    $_ = Base64Encode(shift);
    s,/,_,g;			# is there a better way to do this?

    return $_;
}

#######################################################################
sub Base64UscoreDecode ($) {
    #######################################################################

    $_ = shift;
    s,_,/,g;

    return Base64Decode($_);
}

#######################################################################
sub EncodeURL ($) {
    #######################################################################

    return Base64UscoreEncode(shift);
}

#######################################################################
sub DecodeURL ($) {
    #######################################################################

    # not currently used; perhaps in the future for debugging cache state?

    return Base64UscoreDecode(shift);
}

#######################################################################
sub Retrieve ($$;$) {
    #######################################################################

    my $class   = shift;

    my $force   = $class->{"FORCE"};

    # If sufficiently new, retrieve a URL and store locally.
    my $url     = shift;	   # thing to fetch
    my $dest    = shift;           # where to put it
    my $reftime = shift;	   # optional mod time reference

    # logic: if two args, download if $url more recent that $dest;
    # if three args, instead see if $url at least as recent as $reftime;
    # either way, if $force is set, download regardless
    if (defined $reftime) {
        Debug("Retrieve($url, $dest, [" . scalar localtime($reftime) . '])');
    } else {
        Debug("Retrieve($url, $dest)");
    }

    my $ua = new LWP::UserAgent;
    my $req = new HTTP::Request( GET=>$url );

    # only fetch if changed
    my $mtime = 0;
    unless ($force) {
        if (defined $reftime) {
            Debug("Retrieve: ref time: " . scalar localtime($reftime));
            $req->if_modified_since($reftime - 1);
        } elsif (-f $dest) {
            $mtime = (stat($dest))[9];
            Debug("Retrieve: $dest: last mod: " . scalar localtime($mtime));
            $req->if_modified_since($mtime) if (defined($mtime));
        }
    }

    # set timeout
    $ua->timeout($get_timeout);

    # do the GET
    my $res = $ua->request($req);
  
    # no change?
    if ($res->code() == 304) {
        Debug("Retrieve: <$url>: no change (304)");
        return 0;
    }
  
    # timeout, EOF, etc?
    if ($res->code() == 500) {
        Warn("Retrieve: <$url>: " .$res->content());
        return 2;
    }

    unless($res->is_success()) {
	Warn("can't get: <$url>: " . $res->message() . " (" . $res->code() . ")");
	return 3;
    }

    $mtime = $res->last_modified;
    Debug("Retrieve: <$url>: last mod: " . scalar localtime($mtime));

    ( open(DEST, ">$dest") &&
      (print DEST $res->content()) &&
      close(DEST) ) 
        or Quit("can't save in $dest: $!");
  
    # preserve mtime
    utime($mtime, $mtime, $dest) or return(ERROR, "can't set mtime: $dest: $!");

    return 1;
}

#######################################################################
sub Parse ($) {
    #######################################################################

    # Parse XML profile and return XML::Parser's tree structure.

    my $xmlfile = shift;

    my $xmlParser = new XML::Parser(Style => 'Tree');
    my $tree = eval { $xmlParser->parsefile($xmlfile); };
    Quit("XML parse failed: $xmlfile: $@") if ($@);

    return $tree;
}

#######################################################################
sub DecodeValue ($$) {
    #######################################################################

    # Decode a property value according to encoding attribute.

    my $data = shift;
    my $encoding = shift;

    if ($encoding eq '' or $encoding eq 'none') {
        return $data;
    } elsif ($encoding eq 'base64') {
        my $plain = Base64Decode($data);
        return (defined $plain ? $plain : "invalid data: $data");
    } elsif ($encoding eq 'base64,gzip') {
        my $temp = Base64Decode($data);
        my $plain = (defined $temp ? Gunzip($temp) : undef);
        return (defined $plain ? $plain : "invalid data: $data");
    } else {
        Warn("invalid encoding: $encoding");
        return "invalid data: $data";
    }
}

#######################################################################
sub ComputeChecksum ($) {
    #######################################################################

    # Compute the node profile checksum attribute.

    my $val = shift;
    my $type = $val->{TYPE};
    my $value = $val->{VALUE};
    
    if ($type eq 'nlist') {
        # MD5 of concat of children & their checksums, in order
        my @children = sort keys %$value;
        return md5_hex(join('',
                            map { ($_, $value->{$_}->{CHECKSUM}); }
                            @children));
    } elsif ($type eq 'list') {
        # ditto
        my @children = 0..(scalar @$value)-1;
        return md5_hex(join('',
                            map { ($_, $value->[$_]->{CHECKSUM}); }
                            @children));
    } else {
        # assume property: just MD5 of value
        unless (defined $value) {
	    return md5_hex("_<undef>_");
        }
        return md5_hex(encode_utf8($value));
    }
}

#######################################################################
sub InterpretNode ($$) {
    #######################################################################

    # Turn an XML parse node -- a (tag, content) pair -- into a Perl hash
    # representing the corresponding profile data structure.

    my $tag = shift;
    my $content = shift;
    my $att = $content->[0];
    my $val = {};

    # deal with attributes
    $val->{TYPE} = $tag;
    foreach my $a (keys %$att) {
        if ($a eq 'name') {
            $val->{NAME} = $att->{$a};
        } elsif ($a eq 'derivation') {
            $val->{DERIVATION} = $att->{$a};
        } elsif ($a eq 'checksum') {
            $val->{CHECKSUM} = $att->{$a};
        } elsif ($a eq 'acl') {
            $val->{ACL} = $att->{$a};
        } elsif ($a eq 'encoding') {
            $val->{ENCODING} = $att->{$a};
        } elsif ($a eq 'description') {
            $val->{DESCRIPTION} = $att->{$a};
        } elsif ($a eq 'type') {
            $val->{USERTYPE} = $att->{$a};
        } else {
            # unknown attribute
        }
    }

    # work out value
    if ($tag eq 'nlist') {
        my $nlist = {};
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];
            if ($t ne '0' and $t ne '') {
                # ignore text between elements
                my $a = $c->[0];
                my $n = $a->{name};
                $nlist->{$n} = &InterpretNode($t, $c);
            }
        }
        $val->{VALUE} = $nlist;
    } elsif ($tag eq 'list') {
        my $list = [];
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];
            if ($t ne '0' and $t ne '') {
                # ignore text between elements
                push @$list, &InterpretNode($t, $c);
            }
        }
        $val->{VALUE} = $list;
    } elsif ($tag eq 'string' or
	     $tag eq 'double' or
	     $tag eq 'long' or
	     $tag eq 'boolean') {
        # decode if required
        if (defined $val->{ENCODING})
	{
            $val->{VALUE} = DecodeValue($content->[2], $val->{ENCODING});
        } else {
            $val->{VALUE} = $content->[2];
        }
    } else {
        # unknown type: should issue warning, at least
    }
    # compute checksum if missing
    if (not defined $val->{CHECKSUM}) {
        $val->{CHECKSUM} = ComputeChecksum($val);
    }

    return $val;
}

#######################################################################
sub InterpretNodeXMLDB ($$) {
    #######################################################################

    # Turn an XML parse node -- a (tag, content) pair -- into a Perl hash
    # representing the corresponding profile data structure.

    my $tag = shift;
    my $content = shift;
    my $collapse = shift;
    my $att = $content->[0];
    my $val = {};

    # For XMLDB, the tag is the element name (except for special
    # case below for encoded tags).
    $val->{NAME} = $tag;

    # Default type if not specified is an nlist.
    $val->{TYPE} = 'nlist';

    # Deal with all of the attributes.
    foreach my $a (keys %$att) {
        if ($a eq 'type') {
            $val->{TYPE} = $att->{$a};
        } elsif ($a eq 'derivation') {
            $val->{DERIVATION} = $att->{$a};
        } elsif ($a eq 'checksum') {
            $val->{CHECKSUM} = $att->{$a};
        } elsif ($a eq 'acl') {
            $val->{ACL} = $att->{$a};
        } elsif ($a eq 'encoding') {
            $val->{ENCODING} = $att->{$a};
        } elsif ($a eq 'description') {
            $val->{DESCRIPTION} = $att->{$a};
        } elsif ($a eq 'utype') {
            $val->{USERTYPE} = $att->{$a};
        } elsif ($a eq 'unencoded') {
	    # Special case for encoded tags.
            $val->{NAME} = $att->{$a};
        } else {
            # ignore unknown attribute
        }
    }

    # Pull out the type for convenience and the list depth.  Depth of
    # zero means it is not a list.  Depth of one or higher gives the
    # dimensionality of the list. 
    my $type = $val->{TYPE};
    my $my_depth = (defined($att->{list})) ? int($att->{list}) : 0;

    if (($type eq 'nlist')) {

	# Flag to see if this node is eligible to be "collapsed".
	my $collapse = 0;

	# Process nlist and the top-level of lists.
        my $nlist = {};
        my $i = 1;
        while ($i < scalar @$content) {
            my $t = $content->[$i++];
            my $c = $content->[$i++];

	    # Ignore all but text nodes.  May also be a list element
            # which has already been processed before. 
            if ($t ne '0' and $t ne '') {

		my $a = $c->[0];
		my $child_depth = (defined($a->{list})) ? int($a->{list}) : 0;

		# Is the child a list? 
		if ($child_depth==0) {

		    # No, just add the child normally.  Be careful,
		    # with encoded tags the child's name may change.
		    my $result = &InterpretNodeXMLDB($t, $c);
		    $nlist->{$result->{NAME}} = $result;

		} else {

		    # This is the head of a list, create an extra
		    # level.  This may be removed later.  Check to see
		    # if this is necessary.
		    if (($my_depth > 0) and ($child_depth>$my_depth)) {
			$collapse = 1;
		    }

		    # First, create a new node to handle the list
		    # element. 
		    my $vallist = {};
		    $vallist->{NAME} = $t;
		    $vallist->{TYPE} = 'list';

		    # Create a list for the value and process the
		    # current node to add to it. 
		    my $list = [];
		    push @$list, &InterpretNodeXMLDB($t, $c);

		    # Search through the rest of the entries to see if
		    # there are other list elements from this list. 
		    my $j = $i;
		    while ($j < scalar @$content) {
			my $t2 = $content->[$j++];
			my $c2 = $content->[$j++];

			# Same name and child is a list.
			if ($t eq $t2) {
			    my $child_depth2 = $c2->[0]->{list}; 
			    $child_depth2 = 0 unless defined($child_depth2);
			    
			    # Push the value of this node onto the
			    # list, but also zero the name so that it
			    # isn't processed twice. 
			    if ($child_depth == $child_depth2) {
				push @$list, &InterpretNodeXMLDB($t2, $c2);
				$content->[$j-2] = '0';
			    }
			}
		    }

		    # Complete the node and add it the the nlist
		    # parent. 
		    $vallist->{VALUE} = $list;
		    $vallist->{CHECKSUM} = ComputeChecksum($vallist);
		    $nlist->{$t} = $vallist;
		    
		}
	    }
        }

	# Normally just give the value of the nlist to val.  However,
        # if we're embedded into a multidimensional list, cheat the
        # remove an unnecessary level.  Just switch the $vallist
	# reference for $val.  
	if (! $collapse) {

	    # Normal case.  Just set the value to the hash.
	    $val->{VALUE} = $nlist;

	} else {

	    # Splice and dice.  Remove unnecessary level.

	    # Extra error checking.  The list should have exactly one
	    # key in it.
	    my $count = scalar (keys %$nlist);
	    if ($count!=1) {

		# This is an error.  Recover by essentially doing
		# nothing.  But print the information.
		Warn("multidimensional list fixup failed; " .
		     "hash has multiple values");
		$val->{VALUE} = $nlist
	    }

	    # Switch the reference.
	    $val = $nlist->{(keys %$nlist)[0]};
	}

    } elsif ($type eq 'string' ||
	     $type eq 'double' ||
	     $type eq 'long' ||
	     $type eq 'boolean' ||
	     $type eq 'fetch' ||
	     $type eq 'stream' ||
	     $type eq 'link') {
	
        # decode if required
        if (defined $val->{ENCODING}) {
            $val->{VALUE} = DecodeValue($content->[2], $val->{ENCODING});
        } else {
	    # CAL # Empty element causes undefined context.  This
            # shows up with empty strings.  Guard against this. 
	    if (defined($content->[2])) {
		$val->{VALUE} = $content->[2];
	    } elsif ($type eq 'string') {
		$val->{VALUE} = '';
	    }
        }

    } else {
        # unknown type: should issue warning, at least
    }

    # compute checksum if missing
    if (not defined $val->{CHECKSUM}) {
        $val->{CHECKSUM} = ComputeChecksum($val);
    }

    return $val;
}

#######################################################################
sub Interpret ($) {
    #######################################################################

    # Interpret XML parse tree as profile data structure.  Need more sanity
    # checking!

    my $tree = shift;

    # NB: we are being passed element *content*: ref to array
    # made up of tag-content sequences, one per tree node.

    Quit('parse tree not a reference') unless (ref $tree);
    Warn('ignoring subsequent top-level elements') unless (scalar @$tree == 2);

    # Check to see what XML style is in the format attribute.  If 
    # if there is no attribute, then the "pan" style is assumed.
    # Unsupported styles force an exist.
    my $t = $tree->[0];
    my $c = $tree->[1];
    my $a = $c->[0];
    my $format = $a->{format};
    $format = 'pan' unless defined($format);
    
    my $v = undef;
    if ($format eq 'pan') {
	$v = InterpretNode($t, $c);
    } elsif ($format eq 'xmldb') {
	$v = InterpretNodeXMLDB($t, $c);
    } else {
	Quit('unsupported xml style: '.$format);
    }

    # Uncomment this for debugging purposes.
    #Show($v);

    return $v;
}

#######################################################################
sub Show ($;$$) {
    #######################################################################

    # For debugging (not currently available from command line options):
    # display a profile data structure.

    my $s = shift;
    my $indent = shift;
    $indent = '' if (not defined $indent);

    my $name = shift;
    $name = $s->{NAME} if (not defined $name and defined $s->{NAME});
    
    if (defined $name) {
        print $indent . $name . ' (';
    } else {
        print $indent . '(';
    }
    my $first = 1;
    foreach my $a (sort keys %$s) {
        if ($a ne 'NAME' and $a ne 'VALUE' and $a ne 'TYPE') {
            print ',' if (not $first);
            print "$a=\"" . $s->{$a} . '"';
            $first = 0;
        }
    }
    print ')';
    my $v = $s->{VALUE};
    if ($s->{TYPE} eq 'nlist') {
        print "\n";
        foreach my $k (sort keys %$v) {
            &Show($v->{$k}, $indent . '  ');
        }
    } elsif ($s->{TYPE} eq 'list') {
        print "\n";
        my $i = 0;
        foreach my $el (@$v) {
            &Show($el, $indent . '  ', '[' . $i++ . ']');
        }
    } else {
        print ' "' . $v . "\"\n";
    }
}


#######################################################################
sub FileToString ($) {
    #######################################################################

    # Returns first line of file (minus newline) as string.

    my $f = shift;

    open(F, "<$f") or Quit("can't open $f: $!");
    chomp(my $s = <F>);
    close(F);
    return $s;
}

#######################################################################
sub StringToFile ($$) {
    #######################################################################

    # Creates one-line file consisting of string plus newline.

    my $s = shift;
    my $f = shift;

    ( open(F, ">$f") &&
      (print F "$s\n") &&
      close(F) )
        or return(ERROR,"can't write to $f: $!");
}

#######################################################################
sub PreProcess ($$$$) {
    #######################################################################

    # Merge profile and context into combined XML; assume this will be
    # eventually be something like this.

    system "$_[0] $_[1] $_[2] >$_[3]";
}

#######################################################################
sub FilesDiffer ($$) {
    #######################################################################

    # Return 1 if they differ, 0 if the same.

    my $a = shift;
    my $b = shift;

    # ensure names are defined and exist
    if ((not defined($a)) || (! -e "$a") ||
	(not defined($b)) || (! -e "$b")) {
	return 1;
    }

    # first compare sizes
    return 1 if ((stat($a))[7] != (stat($b))[7]);

    # now check line by line
    open(A, "<$a") or Quit("can't open $a: $!");
    open(B, "<$b") or Quit("can't open $b: $!");
    my $aa;
    my $bb;
    while ($aa = <A>) {
        $bb = <B>;
        (close(A) && close(B) && return 1) if ($aa ne $bb)
    }

    close(A) && close(B) && return 0;
}

#######################################################################
sub AddPath ($$$$$;$) {
    #######################################################################

    # Take a profile data structure (subtree) and the path to it, and
    # make all the necessary cache entries.

    my $prefix = shift;
    my $tree = shift;
    my $refeid = shift;
    my $path2eid = shift;
    my $eid2data = shift;
    my $listnum = shift;

    # store path
    my $path = ($prefix eq '/' ? '/' : $prefix . '/')
        . (defined $listnum ? $listnum : $tree->{NAME});
    my $eid = $$refeid++;
    $path2eid->{$path} = pack('L', $eid);

    # store value
    my $value = $tree->{VALUE};
    my $type = $tree->{TYPE};
    if ($type eq 'nlist') {
        # store NULL-separated list of children's names
        my @children = sort keys %$value;
        $eid2data->{pack('L', $eid)} = join(chr(0), @children);
        Debug("AddPath: $path => $eid => " . join('|', @children));
        # recurse
        foreach (@children) {
            &AddPath($path, $value->{$_}, $refeid, $path2eid, $eid2data);
        }
    } elsif ($type eq 'list') {
        # names are integers
        my @children = 0..(scalar @$value)-1;
        $eid2data->{pack('L', $eid)} = join(chr(0), @children);
        Debug("AddPath: $path => $eid => " . join('|', @children));
        # recurse
        foreach (@children) {
            &AddPath($path, $value->[$_], $refeid, $path2eid, $eid2data,
		     $_);
        }
    } else {
        if (defined $value) {
	    $eid2data->{pack('L', $eid)} = encode_utf8($value);
	    Debug("AddPath: $path => $eid => $value");
        } else {
	    Debug("AddPath: $path => <UNDEF value>");
        }
    }

    # store attributes
    my $t = defined $tree->{USERTYPE} ? $tree->{USERTYPE} : $type;
    $eid2data->{pack('L', 1<<28 | $eid)} = $t;
    $eid2data->{pack('L', 2<<28 | $eid)} = $tree->{DERIVATION}
        if (defined $tree->{DERIVATION});
    $eid2data->{pack('L', 3<<28 | $eid)} = $tree->{CHECKSUM}
        if (defined $tree->{CHECKSUM});
    $eid2data->{pack('L', 4<<28 | $eid)} = $tree->{DESCRIPTION}
        if (defined $tree->{DESCRIPTION});
}

#######################################################################
sub MakeDatabase ($$$) {
    #######################################################################

    # Create the cache databases.

    my $profile = shift;
    my $path2eid_db = shift;
    my $eid2data_db = shift;

    my %path2eid;
    my %eid2data;
    tie(%path2eid, 'GDBM_File', $path2eid_db, &GDBM_WRCREAT, 0644)
        or return(ERROR, "can't tie path2eid DB: $!");
    tie(%eid2data, 'GDBM_File', $eid2data_db, &GDBM_WRCREAT, 0644)
        or return(ERROR, "can't tie eid2data DB: $!");

    # walk profile
    my $eid = 0;
    AddPath('', $profile, \$eid, \%path2eid, \%eid2data, '');

    untie(%path2eid) or return(ERROR, "can't untie path2eid DB: $!");
    untie(%eid2data) or return(ERROR, "can't untie eid2data DB: $!");
}

#sub destroyForeignProfile(){
# Destroy the object

#sub DESTROY(){
#	my $self = shift;
#	if ($self->{"FOREIGN"}){
#		if (-d $self->{"CACHE_ROOT"}){
#			Debug("Destroying foreign profile $self->{'CACHE_ROOT'}");
#			rmtree ($self->{"CACHE_ROOT"}, 0, 1);
#		} else {
#			return (ERROR, "Foreign Profile $self->{'CACHE_ROOT'} not present");
#		}
#	}
#}

# Perform operations required to store foreign profiles.

sub enableForeignProfile(){
    my $self = shift;

    Debug("Enabling foreign profile ");

    # Keeping old configuration
    my $cache_root      = $self->{"CACHE_ROOT"};
    my $tmp_dir         = $self->{"TMP_DIR"};
    my $foreign_profile = 1;
    my $old_cache_root  = $cache_root;

    # Create temporary directory
    $tmp_dir = "/var/tmp" unless (defined($tmp_dir));

    return(ERROR, "temporary directory $tmp_dir does not exist")
	unless (-d "$tmp_dir");

    Debug("Creating temporary directory ");
    $cache_root = tempdir(DIR=>$tmp_dir, CLEANUP => 1);
    $self->{"CACHE_ROOT"} = $cache_root;

    # Check existance of required directories in temporary foreign directory
    if (!(-d $cache_root)) {
	Debug("Creating directory: $cache_root");
	mkdir($cache_root, 0755)
	    or return(ERROR, "can't make foreign profile dir: $cache_root: $!");
	mkdir("$cache_root/data", 0755)
	    or return(ERROR, "can't make foreign profile data dir: $cache_root/data: $!");
	mkdir("$cache_root/tmp", 0755)
	    or return(ERROR, "can't make foreign profile tmp dir: $cache_root/tmp: $!");
    } else {
	if (!(-d "$cache_root/data")) {	
	    Debug("Creating $cache_root/data directory "); 
	    unless ((-d "$cache_root/data")) { 
		mkdir("$cache_root/data", 0755)
		    or return(ERROR,
			      "can't make foreign profile data dir: $cache_root/data: $!");
	    }
	}
	if (!(-d "$cache_root/tmp")) {	
	    Debug("Creating $cache_root/tmp directory ");
	    unless ((-d "$cache_root/tmp")) {
		mkdir("$cache_root/tmp", 0755)
		    or return(ERROR,
			      "can't make foreign profile tmp dir: $cache_root/tmp: $!");
	    }
	}
    }

    # Create lock files
    if (!(-f "$cache_root/$FETCH_LOCK_FN")) {
	Debug("Creating lock file in foreign cache root"); 
	StringToFile("", "$cache_root/$FETCH_LOCK_FN");
    }
    if (!(-f "$cache_root/$GLOBAL_LOCK_FN")) {
	Debug("Creating lock file in foreign cache root"); 
	StringToFile("no", "$cache_root/$GLOBAL_LOCK_FN");
    }
}

######################################################################################
# Override configuration parameters
######################################################################################

# Set Cache Root directory
sub setCacheRoot($){
    my $self = shift;
    throw_error ("directory does not exist: $_[0]") unless (-d $_[0]);
    $self->{"CACHE_ROOT"} = $_[0];
    return SUCCESS;
}

# Set preprocessor application
sub setPreprocessor($){
    my $self = shift;
    throw_error ("file does not exist or not executable: $_[0]") unless (-x $_[0]);
    $self->{"PREPROCESSOR"} = $_[0];
    return SUCCESS;
}

# Set CA directory
sub setCADir($){
    my $self = shift;
    throw_error ("CA directory does not exist: $_[0]") unless (-d $_[0]);
    $ca_dir = $_[0];
    return SUCCESS;
}

# Set CA files
sub setCAFile($){
    my $self = shift;
    throw_error ("CA file does not exist: $_[0]") unless (-r $_[0]);
    $ca_file = $_[0];
    return SUCCESS;
}

# Set Key files path
sub setKeyFile($){
    my $self = shift;
    throw_error ("Key file does not exist: $_[0]") unless (-r $_[0]);
    $key_file = $_[0];
    return SUCCESS;
}

sub setCertFile($){
    my $self = shift;
    throw_error ("cert_file does not exist: $_[0]") unless (-r $_[0]);
    $cert_file = $_[0];
    return SUCCESS;
}

sub setConfig(;$){
    my $self = shift;
    $self->_config($_[0]);
}

sub setProfileURL($){
    my $self = shift;
    my $base_url = $self->{"BASE_URL"};
    Debug ("base_url is not defined in configuration") unless (defined $base_url);
    my $prof = $_[0];
    if ($prof =~ m/^http/) {
	$self->{"PROFILE_URL"} = $prof;
    } else {
	$self->{"PROFILE_URL"} = (defined $base_url)? $base_url . "/profile_" . $prof . ".xml" : "profile_" . $prof . ".xml";
    }
    Debug ("URL is ". $self->{"PROFILE_URL"});
    return SUCCESS;
}

sub setContext($){
    my $self = shift;
    $self->{"CONTEXT_URL"} = $_[0];
    return SUCCESS;
}

sub setContextTime($){
    my $self = shift;
    throw_error("Context time should be natural number: $_[0]") unless ($_[0] =~m/^\d+$/) ;
    $context_time = $_[0];
    return SUCCESS;
}

sub setContextnTime($){
    my $self = shift;
    throw_error("Context time should be natural number: $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $context_ntime = $_[0];
    return SUCCESS;
}

sub setProfilenTime($){
    my $self = shift;
    throw_error("Profile time should be natural number: $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $profile_ntime = $_[0];
    return SUCCESS;
}

sub setWorldReadable($){
    my $self = shift;
    throw_error("World readable option should be natural number: $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $self->{"WORLD_READABLE"} = $_[0];
    return SUCCESS;
}

=item setNotificationTime()

  Define notification time, if profile modification time is greater than
  notification time then only the profile will be downloaded

=cut
sub setNotificationTime($){
    my $self = shift;
    throw_error("Notification time should be natural number: $_[0]") unless ($_[0] =~m/^\d+$/ ) ;
    $notification_time = $_[0];
    return SUCCESS;
}

=item setKeyFile()

  Define timeout after which profile fetch will be terminated.

=cut
sub setTimeout($){
    my $self = shift;
    throw_error("Timeout should be natural number: $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $get_timeout = $_[0];
    return SUCCESS;
}

sub setForce($){
    my $self = shift;
    throw_error("Force should be natural number: $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $self->{"FORCE"} = $_[0];
    return SUCCESS;
}

=item setKeyFile()

  Define failover profile url

=cut
sub setProfileFailover($){
    my $self = shift;
    $self->{"PROFILE_FAILOVER"} = $_[0];
    return SUCCESS;
}

=item setKeyFile()

  set debug level

=cut
sub setDebug($){
    my $self = shift;
    throw_error("debug level should be a number : $_[0]")
	unless ($_[0] =~m/^\d+$/) ;
    $debug = $_[0];
    return SUCCESS;
}

sub getCacheRoot($){
    my $self = shift;
    return $self->{"CACHE_ROOT"};
}

sub getProfileURL($){
    my $self = shift;
    return $self->{"PROFILE_URL"};
}

sub getForce($){
    my $self = shift;
    return $self->{"FORCE"};
}

sub getHostName(){
    my $self = shift;
    # Finding hostname
    my $host = basename($self->{"PROFILE_URL"});
    $host =~ s/\.xml$//; $host =~ s/^profile_//;
    return $host;
}

sub trim($){

    $_[0] =~ s/^\s+//g;
    $_[0] =~ s/\s+$//g;
    return $_[0];
}

1;
