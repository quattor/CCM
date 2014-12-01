# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::DB;

=head1 NAME

EDG::WP4::CCM::DB

=head1 SYNOPSIS

  $success = EDG::WP4::CCM::DB->read($HASHREF, $PREFIX);

=head1 DESCRIPTION

This is a wrapper around all access to the profile database
format, which copes with multiple possible data formats.

=over

=head1 Functions

=cut

# Which do we support, DB, CDB, GDBM?
use strict;
use warnings;

use CAF::FileWriter;
use CAF::FileReader;

our $default_format = 'DB_File';
our @db_backends;

BEGIN {
    foreach my $db (qw(DB_File CDB_File GDBM_File)) {
        eval " require $db; $db->import ";
        push( @db_backends, $db ) unless $@;
    }
    if ( !scalar @db_backends ) {
        die("No backends available for CCM\n");
    }
}

# test the supported format; returns undef on success
sub test_supported_format {
    my $dbformat = shift;
    if ( !grep { $_ eq $dbformat } @db_backends ) {
        return ( "unsupported CCM database format '$dbformat': we only support "
              . join( ", ", @db_backends ) );
    }
    return;
};

=item write ($HASHREF, $PREFIX, $FORMAT)

Given a reference to a hash, write out the
hash in a database format. The specific format
to use should be passed in as a string value
of DB_File, GDBM_File or CDB_File. Once
successfully written, the HASHREF will be
untied and does not remain connected to the
persistent storage.

The return value will be undef if no errors
were found, else a string error message will
be returned.

=cut

sub write {
    my ( $hashref, $prefix, $dbformat ) = @_;

    my $supported = test_supported_format($dbformat);
    return $supported if defined($supported);

    my %out;

    my $file = "${prefix}.db";
    if ( $dbformat eq 'DB_File' ) {
        my $d = new DB_File::HASHINFO;
        $d->{cachesize} = 102400;
        tie( %out, $dbformat, $file, &O_RDWR | &O_CREAT, 0640, $d )
          or return "can't tie $prefix DB: $!";
    }
    elsif ( $dbformat eq 'CDB_File' ) {
        # CDB is write-once, we need to create magically...
        # We don't tie, instead we'll just do a create using
        # this hash once the AddPaths have completed
        ;
    }
    elsif ( $dbformat eq 'GDBM_File' ) {
        my $d = tie( %out, $dbformat, $file, &GDBM_WRCREAT, 0640);
        return "can't tie $prefix DB: $!" if (! $d);
        # Default 100 seems ok
        #GDBM_File::setopt($d, &GDBM_CACHESIZE, 100, 1);    
    }

    # Okay, so now we're tied, copy across.
    if ( $dbformat eq 'CDB_File' ) {
        eval {
            unlink("$prefix.tmp");    # ignore return code; we don't care
            CDB_File::create( %$hashref, "${prefix}.db", "${prefix}.tmp" );
        };
        if ($@) {
            return "creating CDB $prefix failed: $@";
        }
    }
    else {
        %out = %$hashref;
        untie(%out) or return "can't untie path2eid DB: $!";
    }
    
    my $fh = CAF::FileWriter->new("${prefix}.fmt");
    print $fh "$dbformat\n";
    $fh->close();
    
    return undef;
}

=item read ($HASHREF, $PREFIX)

Open the database file named by the prefix (the prefix
is the full filename, without any extension). The format
of the database file will be determined by reading the
file ${PREFIX}.fmt. If that file does not exist, then
GDBM_File will be used as a default.

The routine will return an error message if there
is a failure, else undef. If there is no errror, then
the HASHREF will be tied to the specified database.

=cut

sub read {
    my ( $hashref, $prefix ) = @_;

    my $fh = CAF::FileReader->new("${prefix}.fmt");
    my $dbformat = "$fh" || $default_format;
    $fh->close();
    chomp($dbformat);
 
    my $supported = test_supported_format($dbformat);
    return $supported if defined($supported);

    my $file = "${prefix}.db";
    if ( $dbformat eq 'DB_File' ) {
        if ( !tie( %$hashref, $dbformat, $file, &O_RDONLY, 0640 ) ) {
            return "failed to open $dbformat $file: $!";
        }
    }
    elsif ( $dbformat eq 'CDB_File' ) {
        if ( !tie( %$hashref, $dbformat, $file ) ) {
            return "failed to open $dbformat $file: $!";
        }
    }
    elsif ( $dbformat eq 'GDBM_File' ) {
        my $d = tie( %$hashref, $dbformat, $file, &GDBM_READER, 0640);
        return "failed to open $dbformat $file: $!" if (! $d);
        # Default 100 seems ok
        # GDBM_File::setopt($d, &GDBM_CACHESIZE, 100, 1);    
    }

    return undef;
}

1;
