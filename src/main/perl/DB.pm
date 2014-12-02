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

# Init handlers
sub _init_DB_File_read {
    return &O_RDONLY;
};    

sub _init_DB_File_write {
    my $d = new DB_File::HASHINFO;
    $d->{cachesize} = 102400;
    return &O_RDWR | &O_CREAT, $d;
};    

sub _post_tie_DB_File {
    # Do nothing
}

sub _init_GDBM_File_read {
    return &GDBM_READER;
};    

sub _init_GDBM_File_write {
    return &GDBM_WRCREAT;
};    

sub _post_tie_GDBM_File {
    my $tie = shift;
    # Default 100 seems ok
    #GDBM_File::setopt($tie, &GDBM_CACHESIZE, 100, 1);    
}


sub _DB_GDBM_File {
    my ($dbformat, $hashref, $file, $mode) = @_;

    $dbformat = 'DB_File' if ($dbformat ne 'GDBM_File');
    $mode = 'read' if ($mode ne 'write');

    my $method = "_init_${dbformat}_${mode}";
    no strict 'refs';
    my ($flags, @extras) = &$method;
    use strict 'refs';    

    my %out;
    my $to_tie = $hashref; 
    $to_tie = \%out if ($mode eq "write");
    
    my $tie = tie(%$to_tie, $dbformat, $file, $flags, 0640, @extras);
    $method = "_post_tie_${dbformat}";
    no strict 'refs';
    &$method($tie);
    use strict 'refs';    
    if ($tie) {
        if ($mode eq 'write') {
            %out = %$hashref;
            $tie = undef; # avoid "untie attempted while 1 inner references still exist" warnings
            untie(%out) or return "can't untie $dbformat $file: $!";
        }
        return;
    } else {
        return "failed to open $dbformat $file for $mode: $!";
    }    
};

sub _DB_File {
    return _DB_GDBM_File('DB_File', @_);
}    

sub _GDBM_File {
    return _DB_GDBM_File('GDBM_File', @_);
}    

sub _CDB_File {
    my ($hashref, $file, $mode) = @_;
    my $dbformat = 'CDB_File';
    my $err;
    if ($mode eq 'write') {
        eval {
            unlink("$file.tmp");    # ignore return code; we don't care
            CDB_File::create( %$hashref, $file, "$file.tmp" );
        };
        $err = $@;
    } else {
        $err = $! if ( !tie( %$hashref, $dbformat, $file ) );
    }
    if ($err) {
        return "failed to open $dbformat $file for $mode: $err";
    }
    return;
}

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

    my $method = "_${dbformat}";
    no strict 'refs';
    my $err = &$method($hashref, "${prefix}.db", 'write');
    use strict 'refs';
    return $err if (defined($err));

    my $fh = CAF::FileWriter->new("${prefix}.fmt");
    print $fh "$dbformat\n";
    $fh->close();
    
    return;
}

=item read ($HASHREF, $PREFIX)

Open the database file named by the prefix (the prefix
is the full filename, without any extension). The format
of the database file will be determined by reading the
file ${PREFIX}.fmt. If that file does not exist, then
DB_File will be used as a default.

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

    my $method = "_${dbformat}";
    no strict 'refs';
    my $err = &$method($hashref, "${prefix}.db", 'read');
    use strict 'refs';
    return $err if (defined($err));

    return;
}

1;
