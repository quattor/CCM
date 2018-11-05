#${PMpre} EDG::WP4::CCM::CacheManager::DB${PMpost}

=head1 NAME

EDG::WP4::CCM::CacheManager::DB

=head1 SYNOPSIS

    # Class style
    my $db = EDG::WP4::CCM::CacheManager::DB->new($prefix, %opts);
    # Write the hashref to the database file
    $db->write($hashref);
    # Open the database and tie to hashref
    $db->open($hashref);

    # Direct read access to database (combines new and open)
    $success = EDG::WP4::CCM::CacheManager::DB::read($hashref, $prefix);

=head1 DESCRIPTION

This is a wrapper around all access to the profile database
format, which copes with multiple possible data formats.

=head1 Methods

=over

=cut

use parent qw(CAF::Object CAF::Path Exporter);

use CAF::Object qw(SUCCESS);
use CAF::FileWriter;
use CAF::FileReader;
use Module::Load;
use Fcntl;

use Readonly;

our @EXPORT_OK = qw(read_db close_db close_db_all);

# Upon change, modify the write and open pod
Readonly our $DEFAULT_FORMAT => 'DB_File';

our %FORMAT_DISPATCH;
our @db_backends;

BEGIN {
    # Which do we support, DB, CDB, GDBM?
    Readonly::Hash our %FORMAT_DISPATCH => {
        DB_File => sub {return _DB_GDBM_File('DB_File', @_);},
        GDBM_File => sub {return _DB_GDBM_File('GDBM_File', @_);},
        CDB_File => \&_CDB_File,
    };

    my @to_try = sort keys %FORMAT_DISPATCH;
    foreach my $db (@to_try) {
        local $@;
        eval {
            load $db;
            $db->import;
        };
        push(@db_backends, $db) unless $@;
    }
    if (!scalar @db_backends) {
        die("No backends available for CCM (tried @to_try)\n");
    }
}

Readonly::Hash my %DB_GDBM_DISPATCH => {
    DB_File_read => sub {return &O_RDONLY;},
    DB_File_write => sub {
        my $d = new DB_File::HASHINFO;
        $d->{cachesize} = 102400;
        return &O_RDWR | &O_CREAT, $d;
    },

    GDBM_File_read => sub {return &GDBM_READER;},
    GDBM_File_write => sub {return &GDBM_WRCREAT;},
};

# Hashref of open filehandles / ties / references for (C)DB_File ties
#   they are kept here so the filehandles created to set CLOEXEC flag
#   on an read-only DB_File tie (and this prevents them to go out of scope,
#   and closing the underlying filehandle of the tie)
# We need to keep proper track of them, to be able to properly clean them up.
my $_dbs = {};

# Close all _dbs of certain flaovur (e.g. all eid2path)
sub close_db_all
{
    my $flavour = shift;
    foreach my $path (keys %$_dbs) {
        close_db($path) if $path =~ m/$flavour/;
    }
}

# Close a db associated with certain file
sub close_db
{
    my ($path) = @_;

    # proper order:
    #   destroy tie
    #   untie hash
    #   cleanup open filehandles

    undef $_dbs->{$path}->{tie};

    local $@;

    if (defined($_dbs->{$path}->{ref})) {
        eval {
            untie %{$_dbs->{$path}->{ref}};
        };
        undef $_dbs->{$path}->{ref};
    }

    if (defined($_dbs->{$path}->{fh})) {
        eval {
            close $_dbs->{$path}->{fh};
        };
        undef $_dbs->{$path}->{fh};
    };

    delete $_dbs->{$path};
}

# Set FD_CLOEXEC on filehandle
# Return undef on success, error message on failure
sub cloexec
{
    my ($path, $msg) = @_;
    my $flags = fcntl($_dbs->{$path}->{fh}, F_GETFL, 0);
    if (fcntl($_dbs->{$path}->{fh}, F_SETFL, $flags & FD_CLOEXEC)) {
        return;
    } else {
        return "Can't set flags$msg: $!\n";
    }
}

=item new / _initialize

Create a new DB instance using C<prefix>, the filename without extension
(will be used by both the C<.db> file itself and a C<.fmt> format description).

Optional parameters

=over

=item log

A C<CAF::Reporter> instance for logging/reporting.

=back

=cut

sub _initialize
{
    my ($self, $prefix, %opts) = @_;

    $self->{prefix} = $prefix;

    # log
    $self->{log} = $opts{log} if defined($opts{log});

    return SUCCESS;
}

# Interact with DB_File and GDBM_File
sub _DB_GDBM_File
{
    my ($dbformat, $hashref, $file, $mode) = @_;

    $dbformat = 'DB_File' if ($dbformat ne 'GDBM_File');
    $mode     = 'read'    if ($mode ne 'write');

    my ($flags, @extras) = $DB_GDBM_DISPATCH{"${dbformat}_${mode}"}->();

    my %out;
    my $to_tie = $hashref;
    $to_tie = \%out if ($mode eq "write");

    # mode as restricted as possible
    close_db($file);
    $_dbs->{$file}->{ref} = $to_tie;
    $_dbs->{$file}->{tie} = tie(%$to_tie, $dbformat, $file, $flags, oct(600), @extras);

    my $err;
    if ($_dbs->{$file}->{tie}) {
        if ($mode eq 'write') {
            %out = %$hashref;
            close_db($file);
        } else {
            # This is not supported for GDBM
            if ($_dbs->{$file}->{tie}->can('fd')) {
                # do not use dup (this is inspired by the old way to lock DB_File)
                if (open($_dbs->{$file}->{fh}, '<&=', $_dbs->{$file}->{tie}->fd())) {
                    $err = cloexec($file, "from $dbformat $file");
                } else {
                    $err = "Failed to get filehandle from $dbformat $file: $!";
                }
            }
        }
    } else {
        $err = "failed to open $dbformat $file for $mode: $!";
    }

    return $err;
}

# Interact with CDB_File
sub _CDB_File
{
    my ($hashref, $file, $mode) = @_;
    my $dbformat = 'CDB_File';
    my $err;
    if ($mode eq 'write') {
        local $@;
        eval {
            unlink("$file.tmp");    # ignore return code; we don't care
            # Cannot pass filemode, will be determined by umask (but fixed in write())
            CDB_File::create(%$hashref, $file, "$file.tmp");
        };
        $err = $@;
    } else {
        close_db($file);
        $_dbs->{$file}->{ref} = $hashref;
        $_dbs->{$file}->{tie} = tie(%$hashref, $dbformat, $file);
        if ($_dbs->{$file}->{tie}) {
            if ($_dbs->{$file}->{tie}->can('handle')) {
                $_dbs->{$file}->{fh} = $_dbs->{$file}->{tie}->handle();
                $err = cloexec($file, "from $dbformat $file");
            }
        } else {
            $err = $!;
        }
    }
    $err = "failed to open $dbformat $file for $mode: $err" if $err;

    return $err ? $err : undef;
}

=item test_supported_format

Test if C<dbformat> is a supported format.

Returns SUCCESS on success, undef on failure (and sets C<fail> attribute).

=cut

sub test_supported_format
{
    my ($self, $dbformat) = @_;

    if (grep {$_ eq $dbformat} @db_backends) {
        $self->debug(2, "dbformat $dbformat is supported");
    } else {
        return $self->fail("unsupported CCM database format '$dbformat': we only support "
                           . join(", ", @db_backends));
    }
    return SUCCESS;
}

=item write

Given a hashref C<hashref>, write out the
hash in a database format C<dbformat>.
(If C<dbformat> is not defined, the
default format C<DB_File> will be used).

Once successfully written, the C<hashref> will be
untied and does not remain connected to the
persistent storage.

C<perms> is an optional hashref with the file permissions
for both database file and format description
(owner/mode/group, C<CAF::FileWriter> style).

Returns undef on success, a string with error message otherwise.

=cut

sub write
{
    my ($self, $hashref, $dbformat, $perms) = @_;

    $dbformat = $DEFAULT_FORMAT if ! defined($dbformat);

    return $self->{fail} if ! $self->test_supported_format($dbformat);

    my $db_fn = "$self->{prefix}.db";
    $self->verbose("Writing the database to $db_fn using $dbformat");

    my $err = $FORMAT_DISPATCH{$dbformat}->($hashref, $db_fn, 'write');
    return $err if (defined($err));

    # Make a copy of perms
    my %opts = %{$perms || {}};
    # E.g. ProfileCache passes a log instances with the file permissions
    delete $opts{log};

    if ($perms) {
        return $self->{fail} if ! $self->status($db_fn, %opts);
    };

    my $fmt_fn = "$self->{prefix}.fmt";
    $self->verbose("Writing the database format $dbformat to $fmt_fn");

    # Add ourself as log instance
    $opts{log} = $self;

    my $fh = CAF::FileWriter->new($fmt_fn, %opts);
    print $fh "$dbformat\n";
    $fh->close();

    return;
}

=item open

Open the database file.

The format of the database file will be determined by reading
the format file. If that file does not exist, then
default format C<DB_File> will be used.

Returns undef on success, a string with error message otherwise.

On success, the C<hashref> will be tied to the specified database.

=cut

sub open
{
    my ($self, $hashref) = @_;

    my $fh = CAF::FileReader->new("$self->{prefix}.fmt", log => $self);
    my $dbformat = "$fh" || $DEFAULT_FORMAT;
    $fh->close();
    chomp($dbformat);

    return $self->{fail} if ! $self->test_supported_format($dbformat);

    my $db_fn = "$self->{prefix}.db";
    $self->verbose("Reading the database to $db_fn using $dbformat");

    my $err = $FORMAT_DISPATCH{$dbformat}->($hashref, $db_fn, 'read');
    return $err;
}

=back

=head1 Functions

=over

=item read_db

Given C<hashref> and C<prefix>, create a new instance
using C<prefix> (and any other options)
and return the C<open>ed database with hashref.

C<read_db> function is exported

=cut

sub read_db
{
    my ($hashref, $prefix, %opts) = @_;

    my $db = EDG::WP4::CCM::CacheManager::DB->new($prefix, %opts);
    return $db->open($hashref);
}


=item read

An alias for read_db (not exported, kept for legacy).

=cut

sub read
{
    return read_db(@_);
}

=pod

=back

=cut

1;
