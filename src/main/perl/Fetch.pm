# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
package      EDG::WP4::CCM::Fetch;

=head1 NAME

EDG::WP4::CCM::Fetch

=head1 SYNOPSIS

  $fetch = EDG::WP4::CCM::Fetch->new({PROFILE_URL => "profile_url or hostname",
                      CONFIG  => "path of config file",
                      FOREIGN => "1/0"});


  $fetch->fetchProfile();

=head1 DESCRIPTION

Module provides Fetch class. This helps in retrieving XML profiles and
contexts from specified URLs. It allows users to retrieve local, as
well as foreign node profiles.

=head1 Functions

=over

=cut

use strict;
use Getopt::Long;
use EDG::WP4::CCM::CCfg qw(getCfgValue);
use EDG::WP4::CCM::DB;
use CAF::Lock qw(FORCE_IF_STALE);
use CAF::FileEditor;
use CAF::FileWriter;
use MIME::Base64;
use LWP::UserAgent;
use XML::Parser;
use Compress::Zlib;
use Digest::MD5 qw(md5_hex);
use Sys::Hostname;
use File::Basename;
use LC::Exception qw(SUCCESS throw_error);
use LC::File;
use LC::Stat qw(:ST);
use File::Temp qw (tempfile tempdir);
use File::Path qw(mkpath rmtree);
use Encode qw(encode_utf8);
use GSSAPI;
use JSON::XS v2.3.0 qw(decode_json);
use Carp qw(carp confess);
use HTTP::Message;

use constant DEFAULT_GET_TIMEOUT => 30;

# Which do we support, DB, CDB, GDBM?
our @db_backends;
BEGIN {
    foreach my $db (qw(DB_File CDB_File GDBM_File)) {
        eval " require $db; $db->import "; push(@db_backends, $db) unless $@;
    }
    if (!scalar @db_backends) {
        die("No backends available for CCM\n");
    }
}

use constant NOQUATTOR => "/etc/noquattor";
use constant NOQUATTOR_EXITCODE => 3;
use constant NOQUATTOR_FORCE => "force-quattor";

use constant MAXPROFILECOUNTER => 9999 ;
use constant ERROR => -1 ;
use parent qw(Exporter CAF::Reporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw($GLOBAL_LOCK_FN $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN
		    ComputeChecksum NOQUATTOR NOQUATTOR_EXITCODE);

# LWP should use Net::SSL (provided with Crypt::SSLeay)
# and Net::SSL doesn't support hostname verify
$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = 'Net::SSL';
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $ec = LC::Exception::Context->new->will_store_errors;

my $GLOBAL_LOCK_FN = "global.lock";
my $FETCH_LOCK_FN  = "fetch.lock";

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

sub new {

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

    return $self;
}

sub _config($){
    my ($self, $cfg, $param) = @_;

    unless (EDG::WP4::CCM::CCfg::initCfg($cfg)){
        $ec->rethrow_error();
        return();
    }

    foreach my $p (qw(debug get_timeout cert_file ca_file ca_dir force base_url
		      profile_failover context_url cache_root cert_file key_file
		      ca_file ca_dir lock_retries lock_wait retrieve_retries
		      retrieve_wait preprocessor world_readable tmp_dir dbformat)) {
	$self->{uc($p)} ||= $param->{uc($p)} || getCfgValue($p);
    }

    $self->setProfileURL(($param->{PROFILE_URL} || $param->{PROFILE} ||
			     getCfgValue('profile')));
    if (getCfgValue('trust')) {
        $self->{"TRUST"} = [split(/\,\s*/, getCfgValue('trust'))];
    } else {
        $self->{"TRUST"} = [];
    }

    $self->{CACHE_ROOT} =~ m{^([-.:\w/]+)$} or
      die "Weird root for cache: $self->{CACHE_ROOT} on profile $self->{PROFILE_URL}";
    $self->{CACHE_ROOT} = $1;
    if ($self->{TMP_DIR}) {
	$self->{TMP_DIR} =~ m{^([-.\w/:]*)$} or
	    die "Weird temp directory: $self->{TMP_DIR} on profile $self->{PROFILE_URL}";
	$self->{TMP_DIR} = $1;

    }
    $self->{DBFORMAT} =~ m{^([a-zA-Z]\w+)(::[a-zA-Z]\w+)*$}
      or die "Weird cache format $self->{DBFORMAT} for profile $self->{PROFILE_URL}";
    $self->{DBFORMAT} = $1;
    map(defined($_) && chomp, values(%$self));

    return SUCCESS;
}


sub setupHttps
{
    my ($self) = @_;

    $ENV{'HTTPS_CERT_FILE'}   = $self->{CERT_FILE} if (defined($self->{CERT_FILE}));
    $ENV{'HTTPS_KEY_FILE'}    = $self->{KEY_FILE} if (defined($self->{KEY_FILE}));
    $ENV{'HTTPS_CA_FILE'}     = $self->{CA_FILE} if (defined($self->{CA_FILE}));
    $ENV{'HTTPS_CA_DIR'}      = $self->{CA_DIR} if (defined($self->{CA_DIR}));
}

# Sets up the required locks in the cache root.  It requires a
# CAF::Lock for the profile itself, and another one, "global.lock" to
# avoid breaking EDG::WP4::CCM::Configuration.
sub getLocks
{
    my ($self) = @_;

    my $fl = CAF::Lock->new("$self->{CACHE_ROOT}/$FETCH_LOCK_FN");
    $fl->set_lock($self->{LOCK_RETRIES}, $self->{LOCK_WAIT}, FORCE_IF_STALE) or
	die "Failed to lock $self->{CACHE_ROOT}/$FETCH_LOCK_FN";
    my $global = CAF::FileWriter->new("$self->{CACHE_ROOT}/$GLOBAL_LOCK_FN",
				      log => $self);
    print $global "no\n";
    $global->close();
    return $fl;

}

=pod

=item retrieve

Stores $url into $cache if it's newer than $time, or if $self->{FORCE}
is set.

It returns undef in case of error, 0 if it there were no changes (the
server returned a 304 code) and a C<CAF::FileWriter> object with the
downloaded contents if they had to be downloaded.

Should be called ony by C<download>

=cut

sub retrieve
{
    my ($self, $url, $cache, $time) = @_;

    my $ua = LWP::UserAgent->new();
    my $rq = HTTP::Request->new(GET => $url);

    my $ht = scalar(localtime($time));
    if (!$self->{FORCE}) {
	$self->debug(1, "Retrieve if newer than $ht");
	$rq->if_modified_since($time);
    }
    $ua->timeout($self->{GET_TIMEOUT});
    $rq->header("Accept-Encoding" => join (" ", qw(gzip x-gzip x-bzip2 deflate)));
    my $rs = $ua->request($rq);
    if ($rs->code() == 304) {
	$self->verbose("No changes on $url since $ht");
	return 0;
    }

    if (!$rs->is_success()) {
	$self->warn("Got an unexpected result while retrieving $url: ", $rs->code(),
		    " ", $rs->message());
	return;
    }

    my $cnt;
    if ($rs->content_encoding() && $rs->content_encoding() eq 'krbencrypt') {
        my ($author, $payload) = $self->_gss_decrypt($rs->content());
        if ($self->{TRUST} && !grep($author =~ $_, @{$self->{TRUST}})) {
            die ("Refusing profile generated by $author");
        }
        $cnt = $payload;
    }
    else {
        $cnt = $rs->decoded_content();
    }

    my $fh = CAF::FileWriter->new($cache, log => $self);
    print $fh $cnt;

    if (!utime($rs->last_modified(), $rs->last_modified(), $cache)) {
	$self->warn("Unable to set mtime for $cache: $!");
    }

    return $fh;
}

=pod

=item download

Downloads the files associated with $type (profile or context). In
case of error it retries $self->{RETRIEVE_RETRIES} times, falling back
to a failover URL if necessary (thus up to 2*$self->{RETRIEVE_RETRIES}
may happen.

Returns -1 in case of error, 0 if nothing had to be retrieved (files
in the server were older than our local cache) and a C<CAF::FileWriter>
object with the downloaded contents, if something was actually
downloaded.

=cut

sub download
{
    my ($self, $type) = @_;

    my $url = $self->{uc($type) . "_URL"};

    my $cache = sprintf("%s/data/%s", $self->{CACHE_ROOT}, $self->EncodeURL($url));

    if (! -f $cache) {
	CAF::FileWriter->new($cache, log => $self)->close();
    }

    my @st = stat($cache) or die "Unable to stat profile cache: $cache ($!)";

    foreach my $u (($url, $self->{uc($type) . "_FAILOVER"})) {
	for my $i (1..$self->{RETRIEVE_RETRIES}) {
	    my $rt = $self->retrieve($u, $cache, $st[ST_CTIME]);
	    return $rt if defined($rt);
	    $self->debug(1, "$u: try $i of $self->{RETRIEVE_RETRIES}: ",
			 "sleeping for $self->{RETRIEVE_WAIT} seconds");
	    sleep($self->{RETRIEVE_WAIT});
	}
    }
    return undef;
}

sub previous
{
    my ($self) = @_;

    my ($dir, %ret);

    $ret{cid} = CAF::FileEditor->new("$self->{CACHE_ROOT}/latest.cid",
				     log => $self);

    if ("$ret{cid}" eq '') {
	$ret{cid}->print("0\n");
    }
    $ret{cid} =~ m{^(\d+)\n?$} or die "Invalid CID: $ret{cid}";
    $dir = "$self->{CACHE_ROOT}/profile.$1";
    $ret{url} = CAF::FileEditor->new("$dir/profile.url", log => $self);
    $ret{url}->cancel();
    chomp($ret{url});
    $ret{context_url} = CAF::FileEditor->new("$dir/context.url",
					     log => $self);
    $ret{profile} = CAF::FileEditor->new("$dir/profile.xml",
					 log => $self);

    # We want to read this stuff in a variety of ways, but we *don't*
    # want it written back or modified in disk!!
    $ret{profile}->cancel();
    $ret{context_url}->cancel();

    return %ret;
}

sub current
{
    my ($self, $profile, %previous) = @_;

    my $cid = "$previous{cid}"  + 1;
    $cid %= MAXPROFILECOUNTER;
    $cid =~ m{^(\d+)$} or die "Weird CID: $cid";
    $cid = $1;
    my $dir = "$self->{CACHE_ROOT}/profile.$cid";

    mkpath($dir, { mode => ($self->{WORLD_READABLE} ? 0755:0700)});

    my %current = (url => CAF::FileWriter->new("$dir/profile.url", log => $self),
		   cid => CAF::FileWriter->new("$self->{CACHE_ROOT}/current.cid",
					       log => $self),
		   profile => CAF::FileWriter->new("$dir/profile.xml", log => $self),
		   eiddata => "$dir/eid2data",
		   eidpath => "$dir/path2eid");
    $current{cid}->print("$cid\n");
    $current{url}->print("$self->{PROFILE_URL}\n");
    $current{profile}->print("$profile");
    return %current;
}


=pod

=item fetchProfile()

fetchProfile  fetches the  profile  from  profile  url and keeps it at
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
-1 in case of other failure, C<SUCCESS> in case of successful fetch.

=cut

sub fetchProfile {

    my ($self) = @_;
    my (%current, %previous);


    $self->setupHttps();

    if ($self->{FOREIGN_PROFILE} && $self->enableForeignProfile() == ERROR) {
	$self->error("Unable to enable foreign profiles");
	return ERROR;
    }

    my $lock = $self->getLocks();

    %previous = $self->previous();

    if (!$self->{FORCE} && "$previous{url}" ne $self->{PROFILE_URL}) {
	$self->debug(1, "Current URL $self->{PROFILE_URL} is different ",
		     "from the previous fetched one $previous{url}. ",
		     "Forcing download.");
	$self->{FORCE} = 1;
    }

    local $SIG{__WARN__} = \&carp;


    # the global lock is an indicator if CIDs are locked (no pivots
    # allowed)

    my $profile = $self->download("profile");


    if (!defined($profile)) {
	$self->error("Failed to fetch profile $self->{PROFILE_URL}");
	return undef;
    }

    return SUCCESS unless $profile;

    local $SIG{__DIE__} = sub {
	warn "Cleaning on die";
	$current{cid}->cancel() if $current{cid};
	$previous{cid}->cancel() if $previous{cid};
	$current{profile}->cancel() if $current{profile};
	confess(@_);
    };
    $self->verbose("Downloaded new profile");

    %current = $self->current($profile, %previous);
    if ($self->process_profile("$profile", %current) == ERROR) {
	$self->error("Failed to process profile for $self->{PROFILE_URL}");
	return ERROR;
    }
    $previous{cid}->set_contents("$current{cid}");
    $previous{cid}->close();
    $current{cid}->close();
    return SUCCESS;
}

# Stores a persistent cache in the directories defined by %cur, from a
# retrieved profile. Returns ERROR or SUCCESS.
sub process_profile
{
    my ($self, $profile, %cur) = @_;

    my ($class, $t) = $self->choose_interpreter($profile);
    eval "require $class";
    die "Couldn't load interpreter $class: $@" if $@;
    $t = $class->interpret_node(@$t);
    return $self->MakeDatabase($t, $cur{eidpath}, $cur{eiddata},
			       $self->{DBFORMAT});
}

sub choose_interpreter
{
    my ($self, $profile) = @_;

    my $tree;
    if ($self->{PROFILE_URL} =~ m{json(?:\.gz)?$}) {
	$tree = decode_json($profile);
	return ('EDG::WP4::CCM::JSONProfile', [ 'profile', $tree ]);
    }

    my $xmlParser = new XML::Parser(Style => 'Tree');
    $tree = eval { $xmlParser->parse($profile); };
    die("XML parse of profile failed: $@") if ($@);

    if ($tree->[1]->[0]->{format} eq 'pan') {
	return ('EDG::WP4::CCM::XMLPanProfile', $tree);
    } else {
	die "Invalid profile format.  Did you supply a deprecated XMLDB profile?";
    }
}

#######################################################################
sub RequestLock ($) {
    #######################################################################

    # Try to get a lock; return lock object if successful.

    my ($lock) = @_;

    my $obj = CAF::Lock->new($lock);
    # try once to grab the lock, allow stealing if the lock is stale
    # we consider a lock to be stale if it's 5 mins old.
    if ($obj->set_lock(0, 0, CAF::Lock::FORCE_IF_STALE, 300)) {
        return $obj;
    }
    return undef;
}

#######################################################################
sub ReleaseLock ($$) {
    #######################################################################

    # Release lock on given object (filename for diagnostics).
    my ($self, $obj, $lock) = @_;
    $self->debug(5, "ReleaseLock: releasing: $lock");
    $obj->unlock();
}


#######################################################################
sub Base64Encode ($) {
    #######################################################################

    # Uses MIME::Base64 -- with no breaking result into lines.
    # Always returns a value.

    return encode_base64($_[0], '');
}

#######################################################################
sub Base64Decode ($) {
    #######################################################################

    # Need to catch warnings from MIME::Base64's decode function.
    # Returns undef on failure.

    my ($self, $data, $msg) = @_;
    $SIG{__WARN__} = sub { $msg = $_[0]; };
    my $plain = decode_base64($data);
    $SIG{__WARN__} = 'DEFAULT';
    if ($msg) {
        $msg =~ s/ at.*line [0-9]*.$//;
        chomp($msg);
        $self->warn('base64 decode failed on "'
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

    my ($self, $data) = @_;
    my $plain = Compress::Zlib::memGunzip($data);
    if (not defined $plain) {
        $self->warn('gunzip failed on "' . substr($data, 0, 10) . '"...');
        return undef;
    } else {
        return $plain;
    }
}

#######################################################################
sub Base64UscoreEncode ($) {
    #######################################################################

    # base64, then with "/" -> "_"

    my ($self, $in) = @_;
    $in = Base64Encode($in);
    $in =~ s,/,_,g;		# is there a better way to do this?

    return $in;
}

#######################################################################
sub Base64UscoreDecode ($) {
    #######################################################################

    my ($self, $in) = @_;
    $in =~ s,_,/,g;

    return $self->Base64Decode($in);
}

sub EncodeURL {

    my ($self, $in) = @_;

    return $self->Base64UscoreEncode($in);
}

sub DecodeURL {

    # not currently used; perhaps in the future for debugging cache state?

    return Base64UscoreDecode(@_);
}


sub _gss_die {
    my ($func, $status) = @_;
    my $msg = "GSS Error in $func:\n";
    for my $e ($status->generic_message()) {
        $msg .= "  MAJOR: $e\n";
    }
    for my $e ($status->specific_message()) {
        $msg .= "  MINOR: $e\n";
    }
    die($msg);
}

sub _gss_decrypt {
    my ($self, $inbuf) = @_;

    my ($client, $status);
    my ($authtok, $buf) = unpack('N/a*N/a*', $inbuf);

    my $ctx = GSSAPI::Context->new();
    $status = $ctx->accept(GSS_C_NO_CREDENTIAL, $authtok, GSS_C_NO_CHANNEL_BINDINGS,
      $client, undef, undef, undef, undef, undef);
    $status or _gss_die("accept", $status);

    $status = $client->display(my $client_display);
    $status or _gss_die("display", $status);

    my $outbuf;
    $status = $ctx->unwrap($buf, $outbuf, 0, 0);
    $status or _gss_die("unwrap", $status);

    return ($client_display, $self->Gunzip($outbuf));
}

sub DecodeValue {
    # Decode a property value according to encoding attribute.

    my ($self, $data, $encoding) = @_;

    if ($encoding eq '' or $encoding eq 'none') {
        return $data;
    } elsif ($encoding eq 'base64') {
        my $plain = $self->Base64Decode($data);
        return (defined $plain ? $plain : "invalid data: $data");
    } elsif ($encoding eq 'base64,gzip') {
        my $temp = $self->Base64Decode($data);
        my $plain = (defined $temp ? $self->Gunzip($temp) : undef);
        return (defined $plain ? $plain : "invalid data: $data");
    } else {
        $self->warn("invalid encoding: $encoding");
        return "invalid data: $data";
    }
}

#######################################################################
sub ComputeChecksum ($) {
    #######################################################################

    # Compute the node profile checksum attribute.

    my ($val) = @_;
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

    my ($self, $tag, $content) = @_;
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
                $nlist->{$n} = $self->InterpretNode($t, $c);
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
                push @$list, $self->InterpretNode($t, $c);
            }
        }
        $val->{VALUE} = $list;
    } elsif ($tag eq 'string' or
             $tag eq 'double' or
             $tag eq 'long' or
             $tag eq 'boolean') {
        # decode if required
        if (defined $val->{ENCODING}) {
            $val->{VALUE} = $self->DecodeValue($content->[2], $val->{ENCODING});
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

    my ($self, $tag, $content, $collapse) = @_;
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
		    my $result = $self->InterpretNodeXMLDB($t, $c);
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
		    push @$list, $self->InterpretNodeXMLDB($t, $c);

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
				push @$list, $self->InterpretNodeXMLDB($t2, $c2);
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
		$self->warn("multidimensional list fixup failed; " .
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
            $val->{VALUE} = $self->DecodeValue($content->[2], $val->{ENCODING});
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

sub Interpret
{
    # Interpret XML parse tree as profile data structure.  Need more sanity
    # checking!

    my ($self, $tree) = @_;

    # NB: we are being passed element *content*: ref to array
    # made up of tag-content sequences, one per tree node.

    die('profile parse tree not a reference') unless (ref $tree);
    $self->warn('ignoring subsequent top-level elements') unless (scalar @$tree == 2);

    # Check to see what XML style is in the format attribute.  If
    # if there is no attribute, then the "pan" style is assumed.
    # Unsupported styles force an exist.
    my $t = $tree->[0];
    my $c = $tree->[1];
    my $a = $c->[0];
    my $format = $a->{format};
    $format ||= 'pan';

    my $v = undef;
    if ($format eq 'pan') {
	$v = $self->InterpretNode($t, $c);
    } elsif ($format eq 'xmldb') {
	$v = $self->InterpretNodeXMLDB($t, $c);
    } else {
	die('unsupported xml style in the profile: '.$format);
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

    my ($s, $indent, $name) = @_;
    $indent = '' if (not defined $indent);

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

    my ($f) = @_;

    open(F, "<$f") or die("can't open $f: $!");
    chomp(my $s = <F>);
    close(F);
    return $s;
}

#######################################################################
sub StringToFile ($$) {
    #######################################################################

    # Creates one-line file consisting of string plus newline.

    my ($s, $f) = @_;

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

    my ($a, $b) = @_;

    # ensure names are defined and exist
    if ((not defined($a)) || (! -e "$a") ||
	(not defined($b)) || (! -e "$b")) {
	return 1;
    }

    # first compare sizes
    return 1 if ((stat($a))[7] != (stat($b))[7]);

    # now check line by line
    open(A, "<$a") or die("can't open $a: $!");
    open(B, "<$b") or die("can't open $b: $!");
    my $aa;
    my $bb;
    while ($aa = <A>) {
        $bb = <B>;
        (close(A) && close(B) && return 1) if ($aa ne $bb)
    }

    close(A) && close(B) && return 0;
}

sub AddPath {

    # Take a profile data structure (subtree) and the path to it, and
    # make all the necessary cache entries.
    my ($self, $prefix, $tree, $refeid, $path2eid, $eid2data, $listnum) = @_;

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
        $self->debug(5, "AddPath: $path => $eid => " . join('|', @children));
        # recurse
        foreach (@children) {
            $self->AddPath($path, $value->{$_}, $refeid, $path2eid, $eid2data);
        }
    } elsif ($type eq 'list') {
        # names are integers
        my @children = 0..(scalar @$value)-1;
        $eid2data->{pack('L', $eid)} = join(chr(0), @children);
        $self->debug(5, "AddPath: $path => $eid => " . join('|', @children));
        # recurse
        foreach (@children) {
            $self->AddPath($path, $value->[$_], $refeid, $path2eid, $eid2data,
		     $_);
        }
    } else {
        # Do this because empty string values arrive here as undefined
        my $v = (defined $value) ? $value : '';
        $eid2data->{pack('L', $eid)} = encode_utf8($v);
        if (defined $value) {
	    $self->debug(5, "AddPath: $path => $eid => $value");
        } else {
	    $self->debug(5, "AddPath: $path => <UNDEF value>");
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

sub MakeDatabase
{
    # Create the cache databases.
    my ($self, $profile, $path2eid_db, $eid2data_db, $dbformat) = @_;

    my %path2eid;
    my %eid2data;

    # walk profile
    my $eid = 0;
    $self->AddPath('', $profile, \$eid, \%path2eid, \%eid2data, '');

    my $err = EDG::WP4::CCM::DB::write(\%path2eid, $path2eid_db, $dbformat);
    if ($err) {
	$self->error($err);
        return ERROR;
    }
    $err = EDG::WP4::CCM::DB::write(\%eid2data, $eid2data_db, $dbformat);
    if ($err) {
	$self->error("$err");
	return ERROR;
    }

    return SUCCESS;
}

#sub destroyForeignProfile(){
# Destroy the object

#sub DESTROY(){
#    my ($self) = @_;
#    if ($self->{"FOREIGN"}){
#        if (-d $self->{"CACHE_ROOT"}){
#            $self->debug(5, "Destroying foreign profile $self->{'CACHE_ROOT'}");
#            rmtree ($self->{"CACHE_ROOT"}, 0, 1);
#        } else {
#            return (ERROR, "Foreign Profile $self->{'CACHE_ROOT'} not present");
#        }
#    }
#}

# Perform operations required to store foreign profiles.

sub enableForeignProfile(){
    my ($self) = @_;

    $self->debug(5, "Enabling foreign profile ");

    # Keeping old configuration
    my $cache_root      = $self->{"CACHE_ROOT"};
    my $tmp_dir         = $self->{"TMP_DIR"};
    my $old_cache_root  = $cache_root;

    return(ERROR, "temporary directory $tmp_dir does not exist")
      unless (-d "$tmp_dir");

    # Check existance of required directories in temporary foreign directory
    if (!(-d $cache_root)) {
        $self->debug(5, "Creating directory: $cache_root");
	mkdir($cache_root, 0755)
	  or return(ERROR, "can't make foreign profile dir: $cache_root: $!");
	mkdir("$cache_root/data", 0755)
	  or return(ERROR, "can't make foreign profile data dir: $cache_root/data: $!");
	mkdir("$cache_root/tmp", 0755)
	  or return(ERROR, "can't make foreign profile tmp dir: $cache_root/tmp: $!");
    } else {
	unless ((-d "$cache_root/data")) {
            $self->debug(5, "Creating $cache_root/data directory ");
	    mkdir("$cache_root/data", 0755)
	      or return(ERROR,
			"can't make foreign profile data dir: $cache_root/data: $!");
        }
	unless ((-d "$cache_root/tmp")) {
            $self->debug(5, "Creating $cache_root/tmp directory ");
	    mkdir("$cache_root/tmp", 0755)
	      or return(ERROR,
			"can't make foreign profile tmp dir: $cache_root/tmp: $!");
        }
    }

    # Create global lock file
    if (!(-f "$cache_root/$GLOBAL_LOCK_FN")) {
        $self->debug(5, "Creating lock file in foreign cache root");
        StringToFile("no", "$cache_root/$GLOBAL_LOCK_FN");
    }
}

######################################################################################
# Override configuration parameters
######################################################################################

# Set Cache Root directory
sub setCacheRoot($){
    my ($self, $val) = @_;
    throw_error ("directory does not exist: $val") unless (-d $val);
    $self->{"CACHE_ROOT"} = $val;
    return SUCCESS;
}

# Set preprocessor application
sub setPreprocessor($){
    my ($self, $val) = @_;
    throw_error ("file does not exist or not executable: $val") unless (-x $val);
    $self->{"PREPROCESSOR"} = $val;
    return SUCCESS;
}

# Set CA directory
sub setCADir($){
    my ($self, $val) = @_;
    throw_error ("CA directory does not exist: $val") unless (-d $val);
    $self->{CA_DIR} = $val;
    return SUCCESS;
}

# Set CA files
sub setCAFile($){
    my ($self, $val) = @_;
    throw_error ("CA file does not exist: $val") unless (-r $val);
    $self->{CA_FILE} = $val;
    return SUCCESS;
}

# Set Key files path
sub setKeyFile($){
    my ($self, $val) = @_;
    throw_error ("Key file does not exist: $val") unless (-r $val);
    $self->{KEY_FILE} = $val;
    return SUCCESS;
}

sub setCertFile($){
    my ($self, $val) = @_;
    throw_error ("cert_file does not exist: $val") unless (-r $val);
    $self->{CERT_FILE} = $val;
    return SUCCESS;
}

sub setConfig(;$){
    my ($self, $val) = @_;
    $self->_config($val);
}

sub setProfileURL($){
    my ($self, $prof) = @_;
    $prof = trim($prof);
    my $base_url = $self->{"BASE_URL"};
    $self->debug (5, "base_url is not defined in configuration") unless (defined $base_url);
    if ($prof =~ m{^(?:http|https|ssh|file)://}) {
        $self->{"PROFILE_URL"} = $prof;
    } else {
        $self->{"PROFILE_URL"} = (defined $base_url)? $base_url . "/profile_" . $prof . ".xml" : "profile_" . $prof . ".xml";
    }
    $self->{PROFILE_URL} =~ m{^((?:http|https|ssh|file)://[-/.\?\w:=%&]+)$} or
      die "Invalid profile url $self->{PROFILE_URL}";
    $self->{PROFILE_URL} = $1;
    $self->debug (5, "URL is ". $self->{"PROFILE_URL"});
    return SUCCESS;
}

sub setContext($){
    my ($self, $val) = @_;
    $self->{"CONTEXT_URL"} = $val;
    return SUCCESS;
}

sub setContextTime($){
    my ($self, $val) = @_;
    throw_error("Context time should be natural number: $val") unless ($val =~m/^\d+$/) ;
    $self->{CONTEXT_TIME} = $val;
    return SUCCESS;
}

sub setContextnTime($){
    my ($self, $val) = @_;
    throw_error("Context time should be natural number: $val")
      unless ($val =~m/^\d+$/) ;
    $self->{CONTEXT_NTIME} = $val;
    return SUCCESS;
}

sub setProfilenTime($){
    my ($self, $val) = @_;
    throw_error("Profile time should be natural number: $val")
      unless ($val =~m/^\d+$/) ;
    $self->{PROFILE_NTIME} = $val;
    return SUCCESS;
}

sub setWorldReadable($){
    my ($self, $val) = @_;
    throw_error("World readable option should be natural number: $val")
      unless ($val =~m/^\d+$/) ;
    $self->{"WORLD_READABLE"} = $val;
    return SUCCESS;
}

=item setProfileFormat

Define the profile format. If receives an argument, it will use it
with no further questions. If not, it will try to derive it from the
URL, being:

=over

=item * URLs ending in C<xml> are for XML profiles.

=item * URLs ending in C<json> are for JSON profiles.

=back

and their gzipped equivalents.

=cut

sub setProfileFormat {
    my ($self, $format) = @_;

    if ($format) {
	$self->{PROFILE_FORMAT} = uc($format);
    } elsif ($self->{PROFILE_URL} =~ m{.xml(?:\.gz)?$}) {
	$self->{PROFILE_FORMAT} = "XML";
    } elsif ($self->{PROFILE_URL} =~ m{.json(?:\.gz)?$}) {
	$self->{PROFILE_FORMAT} = "JSON";
    } else {
	return ERROR;
    }
    return SUCCESS;
}

=item setNotificationTime()

Define notification time, if profile modification time is greater than
notification time then only the profile will be downloaded

=cut

sub setNotificationTime($){
    my ($self, $val) = @_;
    throw_error("Notification time should be natural number: $val") unless ($val =~m/^\d+$/ ) ;
    $self->{NOTIFICATION_TIME} = $val;
    return SUCCESS;
}

=item setTimeout()

Define timeout after which profile fetch will be terminated.

=cut

sub setTimeout($){
    my ($self, $val) = @_;
    throw_error("Timeout should be natural number: $val")
      unless ($val =~m/^\d+$/) ;
    $self->{GET_TIMEOUT} = $val;
    return SUCCESS;
}

sub setForce($){
    my ($self, $val) = @_;
    throw_error("Force should be natural number: $val")
      unless ($val =~m/^\d+$/) ;
    $self->{"FORCE"} = $val;
    return SUCCESS;
}

=item setProfileFailover()

Define failover profile url

=cut

sub setProfileFailover($){
    my ($self, $val) = @_;
    $self->{"PROFILE_FAILOVER"} = $val;
    return SUCCESS;
}

sub getCacheRoot($){
    my ($self) = @_;
    return $self->{"CACHE_ROOT"};
}

sub getProfileURL($){
    my ($self) = @_;
    return $self->{"PROFILE_URL"};
}

sub getForce($){
    my ($self) = @_;
    return $self->{"FORCE"};
}

sub getHostName(){
    my ($self) = @_;
    # Finding hostname
    my $host = basename($self->{"PROFILE_URL"});
    $host =~ s/\.xml$//; $host =~ s/^profile_//;
    return $host;
}

sub trim($){

    $_[0] =~ s/^\s+|\s+$//g;
    return $_[0];
}

1;
