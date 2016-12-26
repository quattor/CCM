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

use Readonly;

our @EXPORT_OK = qw(read_db);

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
        load $db;
        $db->import;
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
    my $tie = tie(%$to_tie, $dbformat, $file, $flags, oct(600), @extras);

    if ($tie) {
        if ($mode eq 'write') {
            %out = %$hashref;
            $tie = undef;    # avoid "untie attempted while 1 inner references still exist" warnings
            untie(%out) or return "can't untie $dbformat $file: $!";
        }
    } else {
        return "failed to open $dbformat $file for $mode: $!";
    }

    return;
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
        $err = $! if (!tie(%$hashref, $dbformat, $file));
    }
    if ($err) {
        return "failed to open $dbformat $file for $mode: $err";
    }
    return;
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
    return $err if (defined($err));

    return;
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
