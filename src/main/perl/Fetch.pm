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
use warnings;

use Getopt::Long;
use EDG::WP4::CCM::CCfg qw(getCfgValue @CFG_KEYS);
use EDG::WP4::CCM::DB;
use EDG::WP4::CCM::CacheManager qw($GLOBAL_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN
    $DATA_DN $PROFILE_DIR_N);
use EDG::WP4::CCM::TextRender qw(ccm_format);
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
use JSON::XS v2.3.0 qw(decode_json encode_json);
use Carp qw(carp confess);
use HTTP::Message;
use Readonly;

use constant DEFAULT_GET_TIMEOUT => 30;

# Which do we support, DB, CDB, GDBM?
our @db_backends;

BEGIN {
    foreach my $db (qw(DB_File CDB_File GDBM_File)) {
        eval " require $db; $db->import ";
        push(@db_backends, $db) unless $@;
    }
    if (!scalar @db_backends) {
        die("No backends available for CCM\n");
    }
}

use constant NOQUATTOR          => "/etc/noquattor";
use constant NOQUATTOR_EXITCODE => 3;
use constant NOQUATTOR_FORCE    => "force-quattor";

use constant MAXPROFILECOUNTER => 9999;
use constant ERROR             => -1;
use parent qw(Exporter CAF::Reporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw($GLOBAL_LOCK_FN $FETCH_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN $DATA_DN
    $TABCOMPLETION_FN
    ComputeChecksum NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);

# LWP should use Net::SSL (provided with Crypt::SSLeay)
# and Net::SSL doesn't support hostname verify
$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = 'Net::SSL';
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}    = 0;

my $ec = LC::Exception::Context->new->will_store_errors;

Readonly our $FETCH_LOCK_FN => "fetch.lock";
Readonly our $TABCOMPLETION_FN => "tabcompletion";

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

    return $self;
}

sub _config($)
{
    my ($self, $cfg, $param) = @_;

    unless (EDG::WP4::CCM::CCfg::initCfg($cfg)) {
        $ec->rethrow_error();
        return ();
    }

    $self->{_CCFG} = $cfg;

    my @keys = qw(tmp_dir context_url);
    push(@keys, @CFG_KEYS);
    foreach my $p (@keys) {
        # do not override any predefined uppercase attributes
        $self->{uc($p)} ||= $param->{uc($p)} || getCfgValue($p);
    }

    $self->setProfileURL(($param->{PROFILE_URL} || $param->{PROFILE} || getCfgValue('profile')));
    if (getCfgValue('trust')) {
        $self->{"TRUST"} = [split(/\,\s*/, getCfgValue('trust'))];
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

sub setupHttps
{
    my ($self) = @_;

    $ENV{'HTTPS_CERT_FILE'} = $self->{CERT_FILE}
        if (defined($self->{CERT_FILE}));
    $ENV{'HTTPS_KEY_FILE'} = $self->{KEY_FILE}
        if (defined($self->{KEY_FILE}));
    $ENV{'HTTPS_CA_FILE'} = $self->{CA_FILE} if (defined($self->{CA_FILE}));
    $ENV{'HTTPS_CA_DIR'}  = $self->{CA_DIR}  if (defined($self->{CA_DIR}));
}

# Sets up the required locks in the cache root.  It requires a
# CAF::Lock for the profile itself, and another one, "global.lock" to
# avoid breaking EDG::WP4::CCM::Configuration.
sub getLocks
{
    my ($self) = @_;

    my $fl = CAF::Lock->new("$self->{CACHE_ROOT}/$FETCH_LOCK_FN");
    $fl->set_lock($self->{LOCK_RETRIES}, $self->{LOCK_WAIT}, FORCE_IF_STALE)
        or die "Failed to lock $self->{CACHE_ROOT}/$FETCH_LOCK_FN";
    my $global = CAF::FileWriter->new("$self->{CACHE_ROOT}/$GLOBAL_LOCK_FN", log => $self);
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
    $rq->header("Accept-Encoding" => join(" ", qw(gzip x-gzip x-bzip2 deflate)));
    my $rs = $ua->request($rq);
    if ($rs->code() == 304) {
        $self->verbose("No changes on $url since $ht");
        return 0;
    }

    if (!$rs->is_success()) {
        $self->warn("Got an unexpected result while retrieving $url: ",
            $rs->code(), " ", $rs->message());
        return;
    }

    my $cnt;
    if ($rs->content_encoding() && $rs->content_encoding() eq 'krbencrypt') {
        my ($author, $payload) = $self->_gss_decrypt($rs->content());
        if ($self->{TRUST} && !grep($author =~ $_, @{$self->{TRUST}})) {
            die("Refusing profile generated by $author");
        }
        $cnt = $payload;
    } else {
        $cnt = $rs->decoded_content();
    }

    my $fh = CAF::FileWriter->new($cache, log => $self);
    print $fh $cnt;
    $fh->close();

    my $modified = $rs->last_modified();

    if ($modified) {
        my $now = time();
        if ($now < $modified) {
            $self->warn("Profile has last_modified timestamp ",
                        $modified - $now,
                        " seconds in future (timestamp $modified)");
        }

        if (! utime($modified, $modified, $cache)) {
            $self->warn("Unable to set mtime for $cache: $!");
        }
    } else {
        $self->warn("Unable to set mtime for $cache: last_modified is undefined");
    }

    $fh = CAF::FileReader->new($cache, log => $self);
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

    my $cache = join("/", $self->{CACHE_ROOT}, $DATA_DN, $self->EncodeURL($url));

    if (!-f $cache) {
        CAF::FileWriter->new($cache, log => $self)->close();
    }

    my @st = stat($cache) or die "Unable to stat profile cache: $cache ($!)";

    my @urls = ($url);
    push @urls, split(/,/, $self->{uc($type) . "_FAILOVER"})
        if defined($self->{uc($type) . "_FAILOVER"});

    foreach my $u (@urls) {
        next if (!defined($u));
        for my $i (1 .. $self->{RETRIEVE_RETRIES}) {
            my $rt = $self->retrieve($u, $cache, $st[ST_MTIME]);
            return $rt if defined($rt);
            $self->debug(
                1,
                "$u: try $i of $self->{RETRIEVE_RETRIES}: ",
                "sleeping for $self->{RETRIEVE_WAIT} seconds"
            );
            sleep($self->{RETRIEVE_WAIT});
        }
    }
    return undef;
}

# Previous is a bit of a misnomer. This is about the "latest.cid"
sub previous
{
    my ($self) = @_;

    my ($dir, %ret);

    $ret{cid} = CAF::FileEditor->new("$self->{CACHE_ROOT}/$LATEST_CID_FN", log => $self);

    if ("$ret{cid}" eq '') {
        $ret{cid}->print("0\n");
    }
    $ret{cid} =~ m{^(\d+)\n?$} or die "Invalid CID: $ret{cid}";

    $dir = "$self->{CACHE_ROOT}/$PROFILE_DIR_N$1";
    $ret{dir} = $dir;

    $ret{url} = CAF::FileReader->new("$dir/profile.url", log => $self);
    chomp($ret{url}); # this actually works

    $ret{context_url} = CAF::FileReader->new("$dir/context.url", log => $self);
    $ret{profile}     = CAF::FileReader->new("$dir/profile.xml", log => $self);

    return %ret;
}

# returns the new soon to be current CID
sub current
{
    my ($self, $profile, %previous) = @_;

    my $cid = "$previous{cid}" + 1;
    $cid %= MAXPROFILECOUNTER;
    $cid =~ m{^(\d+)$} or die "Weird CID: $cid";
    $cid = $1;
    my $dir = "$self->{CACHE_ROOT}/$PROFILE_DIR_N$cid";

    mkpath($dir, {mode => ($self->{WORLD_READABLE} ? 0755 : 0700)});

    my %current = (
        dir => $dir,
        url => CAF::FileWriter->new("$dir/profile.url", log => $self),
        cid => CAF::FileWriter->new(
            "$self->{CACHE_ROOT}/$CURRENT_CID_FN", log => $self
        ),
        profile => CAF::FileWriter->new("$dir/profile.xml", log => $self),
        eiddata => "$dir/eid2data",
        eidpath => "$dir/path2eid"
    );

    # Prepare new profile/CID to become current one
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

sub fetchProfile
{

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

    if (!defined($profile)) {
        $self->error("Failed to fetch profile $self->{PROFILE_URL}");
        return undef;
    }

    return SUCCESS unless $profile;

    local $SIG{__DIE__} = sub {
        warn "Cleaning on die";
        $current{cid}->cancel()     if $current{cid};
        $previous{cid}->cancel()    if $previous{cid};
        $current{profile}->cancel() if $current{profile};
        confess(@_);
    };
    $self->verbose("Downloaded new profile");

    %current = $self->current($profile, %previous);
    if ($self->process_profile("$profile", %current) == ERROR) {
        $self->error("Failed to process profile for $self->{PROFILE_URL}");
        return ERROR;
    }

    # Make the new profile/CID the latest.cid
    my $new_cid = "$current{cid}";

    $previous{cid}->set_contents($new_cid);
    $previous{cid}->close();

    # Make the new profile/CID the current.cid
    $current{cid}->close();

    # TODO do we need a different/additonal control for foreign tabcompletion
    # (i.e. does tabcompletion on foreign profiles make any sense)
    # Do not check return code, this is not fatal or anything.
    # An error is logged in case of problem
    $self->generate_tabcompletion($new_cid) if $self->{TABCOMPLETION};

    return SUCCESS;
}

# Generate the tabcompletion file
sub generate_tabcompletion
{
    my ($self, $cid) = @_;

    my $cmgr = EDG::WP4::CCM::CacheManager->new($self->{CACHE_ROOT}, $self->{_CCFG});
    my $cfg = $cmgr->getLockedConfiguration(undef, $cid);
    my $el = $cfg->getElement('/');
    my $fmt = ccm_format('tabcompletion', $el);

    if (defined $fmt->get_text()) {
        my $fh = $fmt->filewriter("$cfg->{cfg_path}/$TABCOMPLETION_FN", log => $self);
        $fh->close();
    } else {
        $self->error("Failed to render tabcompletion: $fmt->{fail}")
    }

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
    return $self->MakeDatabase($t, $cur{eidpath}, $cur{eiddata}, $self->{DBFORMAT});
}

# custom json_decode that untaints the profile text when using json_typed
sub _decode_json
{
    my ($profile, $typed) = @_;

    my $tree;
    if ($typed) {
        my $tmptree = decode_json($profile);
        # Regenerated profile should be identical
        # (except for some panc xml-encoded string issues,
        #   alphabetic hash order and the prettyfied format)
        #   alphabetic hash order can be fixed with '->canonical(1)', but why bother
        # This assumption is the main reason json_typed works at all.
        # This should also untaint the profile
        my $tmpprofile = encode_json($tmptree);
        $tree = decode_json($tmpprofile);
    } else {
        $tree = decode_json($profile);
    }

    return $tree;
}

sub choose_interpreter
{
    my ($self, $profile) = @_;

    my $tree;
    if ($self->{PROFILE_URL} =~ m{json(?:\.gz)?$}) {
        my $module = "EDG::WP4::CCM::JSONProfile" . ($self->{JSON_TYPED} ? 'Typed' : 'Simple' );
        $tree = _decode_json($profile, $self->{JSON_TYPED});
        return ($module, ['profile', $tree]);
    }

    my $xmlParser = new XML::Parser(Style => 'Tree');
    $tree = eval {$xmlParser->parse($profile);};
    die("XML parse of profile failed: $@") if ($@);

    if ($tree->[1]->[0]->{format} eq 'pan') {
        return ('EDG::WP4::CCM::XMLPanProfile', $tree);
    } else {
        die "Invalid profile format.  Did you supply an unsupported XMLDB profile?";
    }
}

sub RequestLock ($)
{

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

sub ReleaseLock ($$)
{

    # Release lock on given object (filename for diagnostics).
    my ($self, $obj, $lock) = @_;
    $self->debug(5, "ReleaseLock: releasing: $lock");
    $obj->unlock();
}

sub Base64Encode ($)
{

    # Uses MIME::Base64 -- with no breaking result into lines.
    # Always returns a value.

    return encode_base64($_[0], '');
}

sub Base64Decode ($)
{

    # Need to catch warnings from MIME::Base64's decode function.
    # Returns undef on failure.

    my ($self, $data, $msg) = @_;
    $SIG{__WARN__} = sub {$msg = $_[0];};
    my $plain = decode_base64($data);
    $SIG{__WARN__} = 'DEFAULT';
    if ($msg) {
        $msg =~ s/ at.*line [0-9]*.$//;
        chomp($msg);
        $self->warn('base64 decode failed on "' . substr($data, 0, 10) . "\"...: $msg");
        return undef;
    } else {
        return $plain;
    }
}

sub Gunzip ($)
{

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

sub Base64UscoreEncode ($)
{

    # base64, then with "/" -> "_"

    my ($self, $in) = @_;
    $in = Base64Encode($in);
    $in =~ s,/,_,g;    # is there a better way to do this?

    return $in;
}

sub Base64UscoreDecode ($)
{

    my ($self, $in) = @_;
    $in =~ s,_,/,g;

    return $self->Base64Decode($in);
}

sub EncodeURL
{

    my ($self, $in) = @_;

    return $self->Base64UscoreEncode($in);
}

sub DecodeURL
{

    # not currently used; perhaps in the future for debugging cache state?

    return Base64UscoreDecode(@_);
}

sub _gss_die
{
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

sub _gss_decrypt
{
    my ($self, $inbuf) = @_;

    my ($client, $status);
    my ($authtok, $buf) = unpack('N/a*N/a*', $inbuf);

    my $ctx = GSSAPI::Context->new();
    $status =
        $ctx->accept(GSS_C_NO_CREDENTIAL, $authtok, GSS_C_NO_CHANNEL_BINDINGS,
        $client, undef, undef, undef, undef, undef);
    $status or _gss_die("accept", $status);

    $status = $client->display(my $client_display);
    $status or _gss_die("display", $status);

    my $outbuf;
    $status = $ctx->unwrap($buf, $outbuf, 0, 0);
    $status or _gss_die("unwrap", $status);

    return ($client_display, $self->Gunzip($outbuf));
}

sub DecodeValue
{

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

sub ComputeChecksum ($)
{

    # Compute the node profile checksum attribute.

    my ($val) = @_;
    my $type  = $val->{TYPE};
    my $value = $val->{VALUE};

    if ($type eq 'nlist') {

        # MD5 of concat of children & their checksums, in order
        my @children = sort keys %$value;
        return md5_hex(join('', map {($_, $value->{$_}->{CHECKSUM});} @children));
    } elsif ($type eq 'list') {

        # ditto
        my @children = 0 .. (scalar @$value) - 1;
        return md5_hex(join('', map {($_, $value->[$_]->{CHECKSUM});} @children));
    } else {

        # assume property: just MD5 of value
        unless (defined $value) {
            return md5_hex("_<undef>_");
        }
        return md5_hex(encode_utf8($value));
    }
}

sub FilesDiffer ($$)
{

    # Return 1 if they differ, 0 if the same.

    my ($fn1, $fn2) = @_;

    # ensure names are defined and exist
    return 1 if (!(defined($fn1) && -e "$fn1" && defined($fn2) && -e "$fn2"));
    my $fh1 = CAF::FileReader->new($fn1);
    my $fh2 = CAF::FileReader->new($fn2);
    my $differ = "$fh1" ne "$fh2";
    $fh1->close();
    $fh2->close();
    return $differ;
}

sub AddPath
{

    # Take a profile data structure (subtree) and the path to it, and
    # make all the necessary cache entries.
    my ($self, $prefix, $tree, $refeid, $path2eid, $eid2data, $listnum) = @_;

    # store path
    my $path =
        ($prefix eq '/' ? '/' : $prefix . '/') . (defined $listnum ? $listnum : $tree->{NAME});
    my $eid = $$refeid++;
    $path2eid->{$path} = pack('L', $eid);

    # store value
    my $value = $tree->{VALUE};
    my $type  = $tree->{TYPE};
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
        my @children = 0 .. (scalar @$value) - 1;
        $eid2data->{pack('L', $eid)} = join(chr(0), @children);
        $self->debug(5, "AddPath: $path => $eid => " . join('|', @children));

        # recurse
        foreach (@children) {
            $self->AddPath($path, $value->[$_], $refeid, $path2eid, $eid2data, $_);
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
    $eid2data->{pack('L', 1 << 28 | $eid)} = $t;
    $eid2data->{pack('L', 2 << 28 | $eid)} = $tree->{DERIVATION}
        if (defined $tree->{DERIVATION});
    $eid2data->{pack('L', 3 << 28 | $eid)} = $tree->{CHECKSUM}
        if (defined $tree->{CHECKSUM});
    $eid2data->{pack('L', 4 << 28 | $eid)} = $tree->{DESCRIPTION}
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

# Perform operations required to store foreign profiles.

sub enableForeignProfile()
{
    my ($self) = @_;

    $self->debug(5, "Enabling foreign profile.");

    my $tmp_dir        = $self->{"TMP_DIR"};

    return (ERROR, "temporary directory $tmp_dir does not exist")
        unless (-d "$tmp_dir");

    my $cache_root     = $self->{"CACHE_ROOT"};

    # Check existance of required directories in temporary foreign directory
    unless ((-d $cache_root)) {
        $self->debug(5, "Creating directory: $cache_root");
        mkdir($cache_root, 0755)
            or return (ERROR, "can't make foreign profile dir: $cache_root: $!");
    }

    unless ((-d "$cache_root/$DATA_DN")) {
        $self->debug(5, "Creating $cache_root/data directory ");
        mkdir("$cache_root/data", 0755)
            or return (ERROR, "can't make foreign profile data dir: $cache_root/$DATA_DN: $!");
    }

    unless ((-d "$cache_root/tmp")) {
        $self->debug(5, "Creating $cache_root/tmp directory ");
        mkdir("$cache_root/tmp", 0755)
            or return (ERROR, "can't make foreign profile tmp dir: $cache_root/tmp: $!");
    }

    # Create global lock file
    if (!(-f "$cache_root/$GLOBAL_LOCK_FN")) {
        $self->debug(5, "Creating lock file in foreign cache root");
        my $fh = CAF::FileWriter->new("$cache_root/$GLOBAL_LOCK_FN", log => $self);
        print $fh "no\n";
        $fh->close();
    }
}

#
# Override configuration parameters
#

# Set Cache Root directory
sub setCacheRoot($)
{
    my ($self, $val) = @_;
    throw_error("directory does not exist: $val") unless (-d $val);
    $self->{"CACHE_ROOT"} = $val;
    return SUCCESS;
}

# Set preprocessor application
sub setPreprocessor($)
{
    my ($self, $val) = @_;
    throw_error("file does not exist or not executable: $val")
        unless (-x $val);
    $self->{"PREPROCESSOR"} = $val;
    return SUCCESS;
}

# Set CA directory
sub setCADir($)
{
    my ($self, $val) = @_;
    throw_error("CA directory does not exist: $val") unless (-d $val);
    $self->{CA_DIR} = $val;
    return SUCCESS;
}

# Set CA files
sub setCAFile($)
{
    my ($self, $val) = @_;
    throw_error("CA file does not exist: $val") unless (-r $val);
    $self->{CA_FILE} = $val;
    return SUCCESS;
}

# Set Key files path
sub setKeyFile($)
{
    my ($self, $val) = @_;
    throw_error("Key file does not exist: $val") unless (-r $val);
    $self->{KEY_FILE} = $val;
    return SUCCESS;
}

sub setCertFile($)
{
    my ($self, $val) = @_;
    throw_error("cert_file does not exist: $val") unless (-r $val);
    $self->{CERT_FILE} = $val;
    return SUCCESS;
}

sub setConfig(;$)
{
    my ($self, $val) = @_;
    $self->_config($val);
}

sub setProfileURL($)
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

sub setContext($)
{
    my ($self, $val) = @_;
    $self->{"CONTEXT_URL"} = $val;
    return SUCCESS;
}

sub setContextTime($)
{
    my ($self, $val) = @_;
    throw_error("Context time should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{CONTEXT_TIME} = $val;
    return SUCCESS;
}

sub setContextnTime($)
{
    my ($self, $val) = @_;
    throw_error("Context time should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{CONTEXT_NTIME} = $val;
    return SUCCESS;
}

sub setProfilenTime($)
{
    my ($self, $val) = @_;
    throw_error("Profile time should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{PROFILE_NTIME} = $val;
    return SUCCESS;
}

sub setWorldReadable($)
{
    my ($self, $val) = @_;
    throw_error("World readable option should be natural number: $val")
        unless ($val =~ m/^\d+$/);
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

sub setProfileFormat
{
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

sub setNotificationTime($)
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

sub setTimeout($)
{
    my ($self, $val) = @_;
    throw_error("Timeout should be natural number: $val")
        unless ($val =~ m/^\d+$/);
    $self->{GET_TIMEOUT} = $val;
    return SUCCESS;
}

sub setForce($)
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

sub setProfileFailover($)
{
    my ($self, $val) = @_;
    $self->{"PROFILE_FAILOVER"} = $val;
    return SUCCESS;
}

sub getCacheRoot($)
{
    my ($self) = @_;
    return $self->{"CACHE_ROOT"};
}

sub getProfileURL($)
{
    my ($self) = @_;
    return $self->{"PROFILE_URL"};
}

sub getForce($)
{
    my ($self) = @_;
    return $self->{"FORCE"};
}

=pod

=back

=cut

1;
