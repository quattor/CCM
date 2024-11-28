#${PMpre} EDG::WP4::CCM::CacheManager::Encode${PMpost}

# builtin types with magic constants

use Readonly;
use parent qw(Exporter);

# Keep these as constant
use constant {
    UNDEFINED => -1,
    ELEMENT   => 0,
    PROPERTY  => (1 << 0),
    RESOURCE  => (1 << 1),
};

use constant {
    STRING    => ((1 << 2) | PROPERTY),
    LONG      => ((1 << 3) | PROPERTY),
    DOUBLE    => ((1 << 4) | PROPERTY),
    BOOLEAN   => ((1 << 5) | PROPERTY),
    LIST      => ((1 << 2) | RESOURCE),
    NLIST     => ((1 << 3) | RESOURCE),
};

use constant {
    LINK      => ((1 << 9) | STRING),
    TABLE     => NLIST,
    RECORD    => NLIST,
};


Readonly::Hash our %NAME_TYPE_MAP => {
    string => STRING,
    double => DOUBLE,
    long => LONG,
    boolean => BOOLEAN,
    list => LIST,
    nlist => NLIST,
    link => LINK,
    table => TABLE,
    record => RECORD,
};


# sorted names to compute pack'ed values for
# using offset based on index in this array
Readonly::Array our @EIDS_PACK => qw(VALUE TYPE CHECKSUM);

# DB filenames (typically in profilepath)
Readonly our $PATH2EID => 'path2eid';
Readonly our $EID2DATA => 'eid2data';

our @EXPORT    = qw();
our @EXPORT_OK = qw(UNDEFINED ELEMENT PROPERTY RESOURCE STRING
    LONG DOUBLE BOOLEAN LIST NLIST LINK TABLE RECORD
    type_from_name decode_eid encode_eids
    $PATH2EID $EID2DATA @EIDS_PACK
    );

=head1 NAME

EDG::WP4::CCM::CacheManager::Encode - Module with DB encoding functions and constants

=head1 DESCRIPTION

C<EDG::WP4::CCM::CacheManager::Encode> implements the functions
that provide the encoding of metadata in the DB instance used.

The DB is build as follows:

=over

=item In C<EDG::WP4::CCM::Fetch::ProfileCache> the profile is converted to a hashref
with subpath as key and hashref with data and metadata as value.

=item The hashref is walked building up the path and a counter (the C<eid>) is increased for each path

=item The relation between the path and the counter is stored in the C<path2eid> DB with
path as key and encoded eid (using C<< db_keys($eid)->{VALUE} >>) as value.

=item The data and metadata are stored in C<eid2data> DB using the encoded eid (which has offset
for each type of data and metadata) as key and the data as value.

=back

Access to data based on path is possible without en/decoding (C<< eid2data->{path2eid->{$path}} >>).

Access to the metadata however requires decoding of the encoded eid from path2eid; to recompute
the encoded keys for the metadata.

=head2 Type constants:

  ELEMENT
    PROPERTY
      STRING
      LONG
      DOUBLE
      BOOLEAN
      LINK
    RESOURCE
      NLIST
        TABLE
        RECORD
      LIST

=head2 Functions

=over

=item type_from_name

Convert a type in string format into a type constant.

Returns C<UNDEFINED> constant and warns when name is not supported.

=cut

sub type_from_name
{

    my $name = shift;

    if (exists($NAME_TYPE_MAP{$name})) {
        return $NAME_TYPE_MAP{$name};
    } else {
        warn "type_from_name unsupported name $name, returning UNDEFINED ".UNDEFINED;
        return UNDEFINED;
    };
}


=item decode_eid

Return decoded eid.

=cut

sub decode_eid
{
    return unpack('L', shift);
}


=item encode_eids

Given C<eid>, return the keys of the tie'ed DB hashref
for C<VALUE>, C<TYPE> and C<CHECKSUM>
as used in the C<eid2data> DB.

=cut

sub encode_eids
{
    my $eid = shift;

    # 28-bit shift, for 2^28 -1 entries
    return {map {$EIDS_PACK[$_] => pack('L', $_ << 28 | $eid)} 0 .. scalar @EIDS_PACK -1};
};


=pod

=back

=cut

1;
