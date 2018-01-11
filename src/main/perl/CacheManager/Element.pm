#${PMpre} EDG::WP4::CCM::CacheManager::Element${PMpost}

use DB_File;
use File::Spec;
use Encode qw(decode_utf8);
use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager::Resource;
use EDG::WP4::CCM::CacheManager::DB qw(read_db close_db_all);
use EDG::WP4::CCM::CacheManager::Encode qw(
    PROPERTY RESOURCE
    STRING LONG DOUBLE BOOLEAN
    LIST NLIST
    type_from_name decode_eid encode_eids
    $PATH2EID $EID2DATA
    );

use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw();

my $ec = LC::Exception::Context->new->will_store_errors;

=head1 NAME

EDG::WP4::CCM::CacheManager::Element - Element class

=head1 SYNOPSIS

    $eid = $element->getEID();
    $name = $element->getName();
    $path = $element->getPath()
    $type = $element->getType();
    $derivation = $element->getDerivation();
    $checksum = $element->getChecksum();
    $description = $element->getDescription();
    $value = $element->getValue();
    $boolean = $element->isType($type);
    $boolean = $element->isResource();
    $boolean = $element->isProperty();
    $hashref = $element->getRecHash();

=head1 DESCRIPTION

The class C<EDG::WP4::CCM::CacheManager::Element> implements those methods
that are common to all elements and represents a C<Property>.
The class <EDG::WP4::CCM::CacheManager::Element> is a base class for
C<EDG::WP4::CCM::CacheManager::Resource>, which has additional methods.

=over

=item new($config, $ele_path)

Create new Element object. The $config parameter is a Configuration
object with the profile. The $ele_path parameter is the element's
configuration path (it can be either a Path object or a string).

=cut

sub new
{

    my ($proto, $config, $ele_path) = @_;

    my $class = ref($proto) || $proto;

    my $self = {};

    if (@_ != 3) {
        throw_error("usage: Element->new(config, ele_path)");
        return;
    }

    if (!UNIVERSAL::isa($config, "EDG::WP4::CCM::CacheManager::Configuration")) {
        throw_error("usage: Element->new(config, ele_path)");
        return;
    }

    my $prof_dir = $config->getConfigPath();

    # element objects have the following structure

    $self->{CONFIG}      = $config;
    $self->{PROF_DIR}    = $prof_dir;
    $self->{NAME}        = undef;
    $self->{EID}         = undef;
    $self->{PATH}        = undef;           # should be a Path object
    $self->{TYPE}        = undef;           # should a valid TYPE constant)
    $self->{DERIVATION}  = undef;
    $self->{CHECKSUM}    = undef;
    $self->{DESCRIPTION} = undef;
    $self->{VALUE}       = undef;

    # path can be a string or a Path object

    if (UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $self->{PATH} = $ele_path;
    } else {
        $self->{PATH} = EDG::WP4::CCM::Path->new($ele_path);
        if (!$self->{PATH}) {
            throw_error("Path->new ($ele_path)", $ec->error);
            return;
        }
    }

    # LAST is last element (can be undef if this is root element)
    # get_last is Path::_safe_unescaped,
    # LAST is used by getTree, so it should still be possible to
    # use the getTree key to build a subpath,
    # even if is ugly/redundant as name of a subpath
    # (but use NAME for "pretty" last subpath)
    # so safe_unescape should generate the leading/trailing {}
    $self->{LAST} = $self->{PATH}->get_last();

    # NAME is last element or '/'
    # get_last is Path::_safe_unescaped,
    # so NAME can vary if Path's @safe_unescape is non-empty
    # This is a "pretty" name,
    # so safe_unescape should not generate the leading/trailing {}
    $self->{NAME} = $self->{PATH}->depth(1) ? $self->{PATH}->get_last() : '/';

    $self->{ENC_EID} = _resolve_enc_eid($prof_dir, $self->{PATH}->toString());

    if (!defined($self->{ENC_EID})) {
        throw_error("failed to resolve element's encoded ID", $ec->error);
        return;
    }

    $self->{EID} = decode_eid($self->{ENC_EID});

    bless($self, $class);

    if (!$self->_read_metadata()) {
        throw_error("failed to read element's metadata", $ec->error);
        return;
    }

    if (!$self->_read_value()) {
        throw_error("failed to read element's value", $ec->error);
        return;
    }

    return $self;
}

=item _get_tied_db

Wrapper around read_db() to attempt to cache the tied
hash.  Takes a scalar reference (to be filled in with either a new
hash ref or the cached hash ref) instead of a hash ref.

The caching mechanism is extremely conservative and will only cache
the last version of path2eid or eid2path to be accessed.  It makes
the assumption that these files will never change.  (Instead, new
profile data goes into a whole new path.)

=cut

# Hide %CACHE from the rest of the class.  Only the code here can touch it.
{
    my $CACHE = {};

    sub _get_tied_db
    {
        my ($returnref, $path) = @_;
        my ($base) = $path =~ /(\w+)$/;
        if ($CACHE->{$base}->{err}
            or not $CACHE->{$base}->{path}
            or $CACHE->{$base}->{path} ne $path)
        {
            my %newhash = ();
            $CACHE->{$base}->{path} = $path;

            # Cleanup/untie any other references
            close_db_all($base);

            $CACHE->{$base}->{db} = \%newhash;
            $CACHE->{$base}->{err} = read_db(\%newhash, $path);
        }
        $$returnref = $CACHE->{$base}->{db};
        return $CACHE->{$base}->{err};
    }
}

=item elementExists($config, $ele_path)

Returns true if the element identified by $ele_path exists
otherwise false is returned

=cut

sub elementExists
{

    my ($proto, $config, $ele_path) = @_;

    if (@_ != 3) {
        throw_error("usage: Element->elementExists(config, ele_path)");
        return;
    }

    if (! UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $ele_path = EDG::WP4::CCM::Path->new("$ele_path");
    }
    $ele_path = $ele_path->toString();

    my $prof_dir = $config->getConfigPath();

    my $hashref;
    my $err = _get_tied_db(\$hashref, "${prof_dir}/$PATH2EID");
    if ($err) {
        throw_error($err);
        return;
    }

    return (exists($hashref->{$ele_path}));
}

=pod

=item createElement($config, $ele_path)

Create a new Resource or Element object, depending on the type of
the element given by $ele_path. The $config parameter is a Configuration
object with the profile. The $ele_path parameter is the element's
configuration path (it can be either a Path object or a string).

=cut

sub createElement
{

    my ($proto, $config, $ele_path) = @_;

    if (@_ != 3) {
        throw_error("usage: Element->createElement(config, ele_path)");
        return;
    }

    if (! UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $ele_path = EDG::WP4::CCM::Path->new("$ele_path");
    }
    $ele_path = $ele_path->toString();

    my $ele_type = _read_type($config, $ele_path);
    if (!$ele_type) {
        throw_error("Failed to read type of $ele_path", $ec->error);
        return;
    }

    my $element;
    if ($ele_type & PROPERTY) {
        $element = EDG::WP4::CCM::CacheManager::Element->new($config, $ele_path);
        unless ($element) {
            throw_error("Element->new($config, $ele_path)", $ec->error);
            return;
        }
    } elsif ($ele_type & RESOURCE) {
        $element = EDG::WP4::CCM::CacheManager::Resource->new($config, $ele_path);
        unless ($element) {
            throw_error("Resource->new($config, $ele_path)", $ec->error);
            return;
        }
    } else {
        throw_error("wrong element type $ele_path");
        return;
    }

    return ($element);
}

=item getConfiguration()


Returns the element's Configuration object

=cut

sub getConfiguration
{
    my $self = shift;
    return $self->{CONFIG};
}

=item getEID()

Returns the Element ID of the object.

This method is not a part of the NVA-API specification, it may be a subject
to change.

=cut

sub getEID
{
    my $self = shift;
    return $self->{EID};
}

=item getName()

Returns the name of the object

=cut

sub getName
{
    my $self = shift;
    return $self->{NAME};
}

=item getPath()

Returns a Path object with the element's path

=cut

sub getPath
{
    my $self = shift;
    return EDG::WP4::CCM::Path->new($self->{PATH}->toString());
}

=item getType()

Returns the element's type, that is, one of the TYPE_* constans

=cut

sub getType
{
    my $self = shift;
    return $self->{TYPE};
}

=item getDerivation()

Returns the element's derivation

=cut

sub getDerivation
{
    my $self = shift;
    return $self->{DERIVATION};
}

=item getChecksum()

Returns the element's checksum (that is, MD5 digest)

=cut

sub getChecksum
{
    my $self = shift;
    return $self->{CHECKSUM};
}

=item getDescription()

Returns the element's description

=cut

sub getDescription
{
    my $self = shift;
    return $self->{DESCRIPTION};
}

=item getValue()

Returns the element's value, as a string

This method is not a part of the NVA-API specification, it may be a subject
to change.

=cut

sub getValue
{
    my $self = shift;
    return $self->{VALUE};
}

=item isType($type)

Returns true if the element's type match type contained in argument $type

=cut

sub isType
{
    my ($self, $type) = @_;

    if ($type !~ m/^\d+$/) {
        $type = type_from_name($type);
    }

    return (($type & $self->{TYPE}) == $type);
}

=item isResource()

Return true if the element's type is RESOURCE

=cut

sub isResource
{

    my $self  = shift;
    return (RESOURCE & $self->{TYPE});

}

=item isProperty()

Return true if the element's type is PROPERTY

=cut

sub isProperty
{

    my $self = shift;
    return (PROPERTY & $self->{TYPE});

}

=item getTree

Returns a reference to a nested hash composed of all elements below
this element.  Corrected according to the III Quattor Workshop
recomendations. Now, PAN booleans map to Perl booleans, PAN lists map
to Perl array references and PAN nlists map to Perl hash references.

Note that links cannot be followed.

If C<depth> is specified (and not C<undef>), only return the next C<depth>
levels of nesting (and use the Element instances as values).
A C<depth == 0> is the element itself, C<depth == 1> is the first level, ...

Named options

=over

=item convert_boolean

Array ref of anonymous methods to convert the argument
(1 or 0 for resp true and false) to another boolean representation.

=item convert_string

Array ref of anonymous methods to convert the argument
(string value) to another representation/format.

=item convert_long

Array ref of anonymous methods to convert the argument
(integer/long value) to another representation/format.

=item convert_double

Array ref of anonymous methods to convert the argument
(float/double value) to another representation/format.

=item convert_list

Array ref of anonymous methods to convert the argument
(list of elements) to another representation/format.

Each element is already processed before the conversion.

=item convert_nlist

Array ref of anonymous methods to convert the argument
(dict of elements) to another representation/format.

Each element is already processed before the conversion.

=item convert_key

Array ref of anonymous methods to convert the key(s) of the dicts
to another representation/format.

At the end, a stringification of the result is used as key.

=back

The arrayref of anonymous methods are applied as follows:
convert methods C<[a, b, c]> will produce C<$new = c(b(a($old)))>.
(An exception is thrown if these methods are not code references).

=cut

sub getTree
{
    my ($self, $depth, %opts) = @_;

    my ($ret, $el, $nextdepth);
    my $convm = [];

    if (defined($depth)) {
        return $self if ($depth <= 0);
        $nextdepth = $depth - 1;
    }

SWITCH:
    {
        # LIST to array ref
        $self->isType(LIST) && do {
            $ret = [];
            while ($self->hasNextElement) {
                $el = $self->getNextElement();
                push(@$ret, $el->getTree($nextdepth, %opts));
                if ($ec->error) {
                    $ec->rethrow_error;
                    return;
                };
            }
            $convm = $opts{convert_list};
            last SWITCH;
        };

        # NLIST to hashref
        $self->isType(NLIST) && do {
            $ret = {};
            while ($self->hasNextElement) {
                $el = $self->getNextElement();
                # we can use LAST here, as only the root element returns an undef
                # and this cannot be the root element
                # we have to use LAST here, as we want the key to be a valid subpath
                my $key = $el->{LAST};
                if (exists $opts{convert_key}) {
                    # TODO: factor out this code in a ref or anon sub
                    #   for some reason, this is not trivial
                    foreach my $method (@{$opts{convert_key}}) {
                        if (ref($method) eq 'CODE') {
                            local $@;
                            eval {
                                $key = $method->($key);
                            };
                            if ($@) {
                                throw_error("convert_method failed: $@");
                            }
                        } else {
                            throw_error("wrong type ". (ref($method) || 'SCALAR')." for convert_method, must be CODE");
                        }
                    }
                }
                # stringify the resulting key
                $ret->{"$key"} = $el->getTree($nextdepth, %opts);
                if ($ec->error) {
                    $ec->rethrow_error;
                    return;
                };
            }
            $convm = $opts{convert_nlist};
            last SWITCH;
        };

        # BOOLEAN to 1/0
        $self->isType(BOOLEAN) && do {
            $ret = $self->getValue eq 'true' ? 1 : 0;
            $convm = $opts{convert_boolean};
            last SWITCH;
        };

        # No predefined conversion for any other type
        $ret = $self->getValue;

        # STRING
        $self->isType(STRING) && do {
            $convm = $opts{convert_string};
            last SWITCH;
        };

        # LONG
        $self->isType(LONG) && do {
            $convm = $opts{convert_long};
            last SWITCH;
        };

        # DOUBLE
        $self->isType(DOUBLE) && do {
            $convm = $opts{convert_double};
            last SWITCH;
        };

    }

    foreach my $method (@$convm) {
        # TODO: factor out this code in a ref or anon sub
        #   for some reason, this is not trivial
        if (ref($method) eq 'CODE') {
            local $@;
            eval {
                $ret = $method->($ret);
            };
            if ($@) {
                throw_error("convert_method failed: $@");
            }
        } else {
            throw_error("wrong type ". (ref($method) || 'SCALAR')." for convert_method, must be CODE");
        }
    }

    return $ret;
}


#
# _resolve_eid($prof_dir, $ele_path)
#
# Private function that resolve element's encoded id number. $prof_dir is the profile
# full directory path, and $ele_path is the element path (as string)
#
sub _resolve_enc_eid
{
    my ($prof_dir, $ele_path) = @_;

    my $hashref;
    my $err = _get_tied_db(\$hashref, "${prof_dir}/$PATH2EID");
    if ($err) {
        throw_error($err);
        return;
    }

    my $enc_eid = $hashref->{$ele_path};

    if (defined($enc_eid)) {
        return $enc_eid;
    } else {
        throw_error("cannot resolve element $ele_path");
        return;
    }
}


#
# _read_metadata($self)
#
# Private function to read metadata information from DB file.
# $self if a reference to myself (Element) object
#
sub _read_metadata
{

    my $self = shift;

    my ($key, $hashref);

    my $keys = encode_eids($self->{EID});

    my $err = _get_tied_db(\$hashref, "$self->{PROF_DIR}/$EID2DATA");
    if ($err) {
        throw_error($err);
        return;
    }

    foreach my $md (qw(TYPE DERIVATION CHECKSUM DESCRIPTION)) {
        my $val = $hashref->{$keys->{$md}};
        if (defined($val)) {
            $self->{$md} = $val;
        } elsif ($md eq 'DESCRIPTION' || $md eq 'DERIVATION') {
            # metadata attribute "description" is optional
            # TODO: metadata attribute "derivation" should not be optional
            #       but eg none of the JSONProfile have it
            $self->{$md} = "";
        } else {
            throw_error("failed to read element's $md eid $self->{EID}");
            return;
        }
    };

    # convert TYPE to constant
    $self->{TYPE} = type_from_name($self->{TYPE});

    return SUCCESS;
}


#
# _read_type($config, $ele_path)
#
# Private function to read Type information from DB file.
# You do not need an Element object to use this function.
# $config is a configuration profile
# $ele_path is the element path (as string)
#
sub _read_type
{
    my ($config, $ele_path) = @_;

    my $prof_dir = $config->getConfigPath();

    my $enc_eid = _resolve_enc_eid($prof_dir, $ele_path);
    if (!defined($enc_eid)) {
        throw_error("failed to resolve element's encoded ID with path $ele_path", $ec->error);
        return;
    }

    my $hashref;
    my $err = _get_tied_db(\$hashref, "${prof_dir}/$EID2DATA");
    if ($err) {
        throw_error($err);
        return;
    }

    my $eid = decode_eid($enc_eid);
    my $typename = $hashref->{encode_eids($eid)->{TYPE}};

    if (!defined($typename)) {
        throw_error("failed to read element's type with path $ele_path / eid $eid");
        return;
    }

    return type_from_name($typename);
}

#
# _read_value($self)
#
# Private function to read element's value from DB file.
# $self if a reference to myself (Element) object
#
sub _read_value
{

    my $self = shift;

    my $hashref;
    my $err = _get_tied_db(\$hashref, "$self->{PROF_DIR}/$EID2DATA");
    if ($err) {
        throw_error($err);
        return;
    }

    $self->{VALUE} = decode_utf8($hashref->{$self->{ENC_EID}});
    if (!defined($self->{VALUE})) {
        throw_error("failed to read element's value eid $self->{EID}");
        return;
    }

    return SUCCESS;
}

=pod

=back

=cut

1;
