# ${license-info}
# ${developer-info}
# ${author-info}

package EDG::WP4::CCM::Fetch::ProfileCache;

=head1 NAME

EDG::WP4::CCM::Fetch::ProfileCache

=head1 DESCRIPTION

Module provides methods to handle the creation of the profile cache.

=head1 Functions

=over

=cut

use strict;
use warnings;

use EDG::WP4::CCM::DB;

use POSIX;

# Which do we support, DB, CDB, GDBM?
our @db_backends;

BEGIN {
    foreach my $db (qw(DB_File CDB_File GDBM_File)) {
        local $@;
        eval " require $db; $db->import ";
        push(@db_backends, $db) unless $@;
    }
    if (!scalar @db_backends) {
        die("No backends available for CCM\n");
    }
}


use EDG::WP4::CCM::CacheManager qw($GLOBAL_LOCK_FN
    $CURRENT_CID_FN $LATEST_CID_FN
    $DATA_DN $PROFILE_DIR_N);
use EDG::WP4::CCM::TextRender qw(ccm_format);

use CAF::FileWriter;
use CAF::FileReader;
use CAF::Lock qw(FORCE_IF_STALE);
use Digest::MD5 qw(md5_hex);
use Readonly;
use LC::Exception qw(SUCCESS);
use XML::Parser;
use JSON::XS v2.3.0 qw(decode_json encode_json);
use File::Path qw(mkpath);
use Encode qw(encode_utf8);

use constant MAXPROFILECOUNTER => 9999;

use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw(
    $FETCH_LOCK_FN $TABCOMPLETION_FN $ERROR
    ComputeChecksum
    MakeCacheRoot GetPermissions SetMask
);

Readonly our $ERROR => -1;

Readonly our $FETCH_LOCK_FN => "fetch.lock";
Readonly our $TABCOMPLETION_FN => "tabcompletion";

# test if directory exists, for unittestting
sub _directory_exists
{
    my $dir = shift;
    return -d $dir;
}

# Function (possibly method) to obtain the permission and ownership of
# directories and files.
# Arguments
#    C<reporter>: info/error reporter (can be C<$self>, and can be called as C<$self->GetPermissions>).
#    C<group_readable>: the group_readble groupname
#    C<world_readable>: world_readable boolean
# Returns
#    hashref with directory mode and group id (if relevant)
#    hashref with file mode and group id (if relevant)
#    umask mask
sub GetPermissions
{
    my ($reporter, $group_readable, $world_readable) = @_;

    my $gid;
    my $dopts = {
        mode => 0700,
    };
    my $fopts = {
        mode => 0600,
    };
    my $mask = 077;

    if ($group_readable) {
        $gid = getgrnam($group_readable);
        my $msg = "group name for group_readable $group_readable";
        if(defined($gid)) {
            $reporter->verbose("Valid $msg");

            $dopts->{mode} = 0750;
            $dopts->{group} = $gid;

            $fopts->{mode} = 0640;
            $fopts->{group} = $gid;

            $mask = 027;
        } else {
            $reporter->error("Invalid $msg");
        };
    };

    if ($world_readable) {
        if($group_readable) {
            $reporter->info("Both group_readable and world_readable are set, world_readable setting honoured.");
        } else {
            $reporter->verbose("world_readable set")
        }
        $mask = undef;
        $dopts->{mode} = 0755;
        $fopts->{mode} = 0644;
    };

    return $dopts, $fopts, $mask;
};


# Function (possibly method) that sets the umask and changes the current process GID.
# Arguments
#    C<reporter>: info/error reporter (can be C<$self>, and can be called as C<$self->SetMask>).
#    C<mask>: mask
#    C<gid>: (optional) group id
sub SetMask
{
    my ($reporter, $mask, $gid) = @_;

    # make sure files are created so only
    # root and possibly the group can see them
    umask($mask) if $mask;

    if(defined($gid)) {
        # Change gid of this process: files created with
        # umask 027 should be still accessible for this group
        setgid($gid);
        $) = "$gid $gid";
        $( = $gid;
        if ( ( $( != $gid ) or ( $) != $gid ) ) {
            $reporter->error("Failed to set gid $gid");
        };
    };
};


# Function (possibly method) to create cacheroot and optional subdirectories
# with appropiate permissions. Does not return anything.
# Arguments
#    C<reporter>: info/error reporter (can be C<$self>, and can be called as C<$self->MakeCacheRoot>).
#    C<cache_root>: the cacheroot (additionally, also cacheroot/tmp and cacheroot/data are handled)
#    C<dopts>: hashref with directory permissions and group id (if relevant)
#    C<profiledir>: optional relative profile dir path that will receive the permissions
sub MakeCacheRoot
{
    my ($reporter, $cache_root, $dopts, $profiledir) = @_;

    my $gid = $dopts->{group};
    my $dmode = $dopts->{mode};

    # Default paths to set
    my @paths = ($cache_root, "$cache_root/$DATA_DN", "$cache_root/tmp");
    # Add profilepath
    push (@paths, "$cache_root/$profiledir") if ($profiledir && $profiledir =~ m/^\w+\.\d+$/);

    $reporter->verbose("Going to create/modify paths: @paths");

    foreach my $path (@paths) {
        if (_directory_exists($path)) {
            # chmod returns number of changed files, croaks on error
            $reporter->debug(1, "MakeCacheRoot chmod mode $dmode path $path");
            chmod $dmode, $path;
        } else {
            $reporter->debug(1, "MakeCacheRoot mkdir path $path mode $dmode");
            my $ok = mkdir $path, $dmode;
            die "Can't create $path: $!\n" unless $ok;
        }

        # use effective UID
        # chown returns number of changed files, croaks on error
        if (defined($gid)) {
            $reporter->debug(1, "MakeCacheRoot chown uid $> gid $gid path $path");
            chown $>, $gid, $path
        }
    };

}

# Create the globallock file.
# If C<check> is set, check if the file already exists and do not overwrite if it does.
sub createGlobalLock
{
    my ($self, $check) = @_;

    my $fn = "$self->{CACHE_ROOT}/$GLOBAL_LOCK_FN";

    if ($check && -f $fn) {
        $self->debug(1, "Global lock $fn already exists, not overwriting it");
    } else {
        $self->debug(1, "Writing global lock $fn");
        my $global = CAF::FileWriter->new($fn, %{$self->{permission}->{file}});
        print $global "no\n";
        $global->close();
    };
};

# Sets up the required locks in the cache root.  It requires a
# CAF::Lock for the profile itself, and another one, "global.lock" to
# avoid breaking EDG::WP4::CCM::Configuration.
sub getLocks
{
    my ($self) = @_;

    my $fl = CAF::Lock->new("$self->{CACHE_ROOT}/$FETCH_LOCK_FN");
    $fl->set_lock($self->{LOCK_RETRIES}, $self->{LOCK_WAIT}, FORCE_IF_STALE)
        or die "Failed to lock $self->{CACHE_ROOT}/$FETCH_LOCK_FN";
    $self->createGlobalLock();
    return $fl;
}


# Previous is a bit of a misnomer. This is about the "latest.cid"
sub previous
{
    my ($self) = @_;

    my ($dir, %ret);

    $ret{cid} = CAF::FileEditor->new("$self->{CACHE_ROOT}/$LATEST_CID_FN", %{$self->{permission}->{file}});

    if ("$ret{cid}" eq '') {
        $ret{cid}->print("0\n");
    }
    $ret{cid} =~ m{^(\d+)\n?$} or die "Invalid CID: $ret{cid}";

    $dir = "$self->{CACHE_ROOT}/$PROFILE_DIR_N$1";
    $ret{dir} = $dir;

    $ret{url} = CAF::FileReader->new("$dir/profile.url", %{$self->{permission}->{file}});
    chomp($ret{url}); # this actually works

    $ret{context_url} = CAF::FileReader->new("$dir/context.url", %{$self->{permission}->{file}});
    $ret{profile}     = CAF::FileReader->new("$dir/profile.xml", %{$self->{permission}->{file}});

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

    # Doesn't really matter if it's dopts or fopts gid
    my $dopts = $self->{permission}->{directory};
    $self->SetMask($self->{permission}->{mask}, $dopts->{group});
    $self->MakeCacheRoot($self->{CACHE_ROOT}, $dopts, "$PROFILE_DIR_N$cid");

    my %current = (
        dir => $dir,
        url => CAF::FileWriter->new("$dir/profile.url", %{$self->{permission}->{file}}),
        cid => CAF::FileWriter->new(
            "$self->{CACHE_ROOT}/$CURRENT_CID_FN", %{$self->{permission}->{file}}
        ),
        profile => CAF::FileWriter->new("$dir/profile.xml", %{$self->{permission}->{file}}),
        eiddata => "$dir/eid2data",
        eidpath => "$dir/path2eid"
    );

    # Prepare new profile/CID to become current one
    $current{cid}->print("$cid\n");

    $current{url}->print("$self->{PROFILE_URL}\n");
    $current{profile}->print("$profile");
    return %current;
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
        my $fh = $fmt->filewriter("$cfg->{cfg_path}/$TABCOMPLETION_FN", %{$self->{permission}->{file}});
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
    local $@;
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
    local $@;
    $tree = eval {$xmlParser->parse($profile);};
    die("XML parse of profile failed: $@") if ($@);

    if ($tree->[1]->[0]->{format} eq 'pan') {
        return ('EDG::WP4::CCM::XMLPanProfile', $tree);
    } else {
        die "Invalid profile format.  Did you supply an unsupported XMLDB profile?";
    }
}

sub ComputeChecksum
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
        return $ERROR;
    }
    $err = EDG::WP4::CCM::DB::write(\%eid2data, $eid2data_db, $dbformat);
    if ($err) {
        $self->error("$err");
        return $ERROR;
    }

    return SUCCESS;
}

# Perform operations required to store foreign profiles.

sub enableForeignProfile
{
    my ($self) = @_;

    $self->debug(5, "Enabling foreign profile.");

    my $tmp_dir = $self->{"TMP_DIR"};

    return ($ERROR, "temporary directory $tmp_dir does not exist")
        unless (-d "$tmp_dir");

    my $dopts = $self->{permission}->{directory};
    $self->SetMask($self->{permission}->{mask}, $dopts->{group});
    $self->MakeCacheRoot($self->{CACHE_ROOT}, $dopts);

    # Create global lock file
    $self->createGlobalLock(1);
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
        return $ERROR;
    }
    return SUCCESS;
}

=pod

=back

=cut

1;
