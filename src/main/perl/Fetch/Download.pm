# ${license-info}
# ${developer-info}
# ${author-info}

package EDG::WP4::CCM::Fetch::Download;

=head1 NAME

EDG::WP4::CCM::Fetch::Download

=head1 DESCRIPTION

Module provides methods to handle the retrieval of the profiles.

=head1 Functions

=over

=cut

use strict;
use warnings;

use CAF::FileWriter;
use CAF::FileReader;

use EDG::WP4::CCM::CacheManager qw($DATA_DN);

use MIME::Base64;
use Compress::Zlib;

use LC::Stat qw(:ST);

use GSSAPI;
use CAF::Kerberos 16.2.1;

use LWP::UserAgent;
use LWP::Authen::Negotiate;
use HTTP::Request;


# LWP should use Net::SSL (provided with Crypt::SSLeay)
# and Net::SSL doesn't support hostname verify
$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = 'Net::SSL';
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

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

=item retrieve

Stores $url into $cache if it's newer than $time, or if $self->{FORCE}
is set.

It returns undef in case of error, 0 if it there were no changes on the
remote server since C<$time> (the server returned a 304 code)
and a C<CAF::FileWriter> object with the
downloaded contents if they had to be downloaded.

Should be called ony by C<download>.

=cut

sub retrieve
{
    my ($self, $url, $cache, $time) = @_;

    my ($cnt, $krb);
    if ($self->{PRINCIPAL}) {
        $self->verbose("PRINCIPAL $self->{PRINCIPAL} configured, setting up Kerberos environment");
        my $krb_opts = {
            principal => $self->{PRINCIPAL},
            log => $self,
        };
        $krb_opts->{keytab} = $self->{KEYTAB} if $self->{KEYTAB};
        $krb = CAF::Kerberos->new(%$krb_opts);

        return if(! defined($krb->get_context()));

        # set environment to temporary credential cache
        # temporary cache is cleaned-up during destroy of $krb
        $krb->update_env(\%ENV);
    };

    my $ua = LWP::UserAgent->new();
    my $rq = HTTP::Request->new(GET => $url);

    # If human readable time ($ht) is not defined, then treat a 304 repsonse as an error
    my $ht;
    if ($self->{FORCE}) {
        $self->verbose("FORCE set, not setting if_modified_since in request");
    } elsif (! defined($time)) {
        $self->verbose("modification time not defined, not setting if_modified_since in request");
    } else {
        $ht = scalar(localtime($time));
        $self->debug(1, "Retrieve if newer than $ht");
        $rq->if_modified_since($time);
    }

    $ua->timeout($self->{GET_TIMEOUT});
    $rq->header("Accept-Encoding" => join(" ", qw(gzip x-gzip x-bzip2 deflate)));
    my $rs = $ua->request($rq);
    if ($rs->code() == 304) {
        if (defined($ht)) {
            $self->verbose("No changes on $url since $ht");
            return 0;
        } else {
            $self->error("Server responded with code 304 for $url even though ",
                        "if_modified_since was not set in request. No profile retrieved.");
            return;
        }
    }

    if (!$rs->is_success()) {
        $self->warn("Got an unexpected result while retrieving $url: ",
            $rs->code(), " ", $rs->message());
        return;
    }

    if ($rs->content_encoding() && $rs->content_encoding() eq 'krbencrypt') {
        my ($author, $payload) = $self->_gss_decrypt($rs->content());
        if (grep {$author eq $_} @{$self->{TRUST}}) {
            $cnt = $payload;
        } else {
            die("Refusing profile generated by $author");
        }
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

Downloads the files associated with $type (profile). In
case of error it retries $self->{RETRIEVE_RETRIES} times, falling back
to a failover URL if necessary (thus up to 2*$self->{RETRIEVE_RETRIES}
may happen.

Returns undef (or dies) in case of error, or the result from C<retrieve> method otherwise:

=over

=item 0 if nothing had to be retrieved (files in the server were older than our local cache)

=item a C<CAF::FileWriter> object with the downloaded contents, if something was actually
downloaded

=back

=cut

sub download
{
    my ($self, $type) = @_;

    my $url = $self->{uc($type) . "_URL"};

    my $cache = join("/", $self->{CACHE_ROOT}, $DATA_DN, $self->EncodeURL($url));

    my $mtime;
    if (-f $cache) {
        my @st = stat($cache) or die "Unable to stat profile cache: $cache ($!)";
        $mtime = $st[ST_MTIME];
    } else {
        $self->info("No existing cache $cache, not specifying the modification date while retrieving")
    }

    my @urls = ($url);
    push @urls, split(/,/, $self->{uc($type) . "_FAILOVER"})
        if defined($self->{uc($type) . "_FAILOVER"});

    foreach my $u (@urls) {
        next if (!defined($u));
        for my $i (1 .. $self->{RETRIEVE_RETRIES}) {
            my $rt = $self->retrieve($u, $cache, $mtime);
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

sub Base64Encode
{

    # Uses MIME::Base64 -- with no breaking result into lines.
    # Always returns a value.

    return encode_base64($_[0], '');
}

sub Base64Decode
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

sub Gunzip
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

sub Base64UscoreEncode
{

    # base64, then with "/" -> "_"

    my ($self, $in) = @_;
    $in = Base64Encode($in);
    $in =~ s,/,_,g;    # is there a better way to do this?

    return $in;
}

sub Base64UscoreDecode
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


=pod

=back

=cut

1;
