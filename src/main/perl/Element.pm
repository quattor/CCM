# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::Element;

use strict;
use DB_File;
use File::Spec;
use Encode qw(decode_utf8);
use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::Configuration;
use EDG::WP4::CCM::Path;
use EDG::WP4::CCM::Property;
use EDG::WP4::CCM::Resource;
use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw(unescape);
our @EXPORT_OK = qw(UNDEFINED ELEMENT PROPERTY RESOURCE STRING
		    LONG DOUBLE BOOLEAN LIST NLIST LINK TABLE RECORD
                    escape);
our $VERSION = '${project.version}';
use EDG::WP4::CCM::DB;



# builtin types with magic constants

use constant UNDEFINED =>  -1;
use constant ELEMENT   =>   0;
use constant PROPERTY  =>  (1 << 0);
use constant RESOURCE  =>  (1 << 1);
use constant STRING    => ((1 << 2) | PROPERTY);
use constant LONG      => ((1 << 3) | PROPERTY);
use constant DOUBLE    => ((1 << 4) | PROPERTY);
use constant BOOLEAN   => ((1 << 5) | PROPERTY);
use constant LIST      => ((1 << 2) | RESOURCE);
use constant NLIST     => ((1 << 3) | RESOURCE);
use constant LINK      => ((1 << 9) | STRING);
use constant TABLE     => NLIST;
use constant RECORD    => NLIST;

my $ec = LC::Exception::Context->new->will_store_errors;

=head1 NAME

EDG::WP4::CCM::Element - Element class

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

The class Element is a base class for classes Property
and Resource. The class Element implement those methods
that are common to all elments.

Type constants:

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

=over


=cut

=item unescape($string)

Returns an unescaped version of the string. This method is exported
for use with all the components that deal with escaped keys.

=cut

sub unescape ($)
{
    my $str = shift;
    $str =~ s!(_[0-9a-f]{2})!sprintf ("%c", hex($1))!eg;
    return $str;
}


=pod

=item escape($string)

Returns an escaped version of the string.  This method is exported on
demand for use with all tools that have to escape and unescape values.

=cut

sub escape
{
    my $str = shift;

    $str =~ s/(^[0-9]|[^a-zA-Z0-9])/sprintf("_%lx", ord($1))/eg;
    return $str;
}

=item new($config, $ele_path)

Create new Element object. The $config parameter is a Configuration
object with the profile. The $ele_path parameter is the element's
configuration path (it can be either a Path object or a string).

=cut


sub new {

    my $proto = shift;
    my $class = ref($proto) || $proto;

    my ($config, $ele_path, $prof_dir);
    my $self = {};

    if (@_ != 2) {
        throw_error ("usage: Element->new(config, ele_path)");
	return();
    }

    $config    = shift;		# profile's directory path

    if (!UNIVERSAL::isa($config, "EDG::WP4::CCM::Configuration")) {
        throw_error ("usage: Element->new(config, ele_path)");
	return();
    }

    $ele_path  = shift;		# element's configuration path
    $prof_dir  = $config->getConfigPath();

    # element objects have the following structure

    $self->{CONFIG}      = $config;
    $self->{PROF_DIR}    = $prof_dir;
    $self->{NAME}        = undef;
    $self->{EID}         = undef;
    $self->{PATH}        = undef;	# should be a Path object
    $self->{TYPE}        = undef;	# should a valid TYPE constant)
    $self->{DERIVATION}  = undef;
    $self->{CHECKSUM}    = undef;
    $self->{DESCRIPTION} = undef;
    $self->{VALUE}       = undef;

    # path can be a string or a Path object

    if (UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $self->{PATH} = $ele_path;
        $ele_path = $ele_path->toString();
    } else {
        $self->{PATH} = EDG::WP4::CCM::Path->new ($ele_path);
        if (!$self->{PATH}) {
            throw_error("Path->new ($ele_path)", $ec->error);
            return ();
        }
    }

    $self->{NAME} = $self->{PATH}->toString();
    $self->{NAME} =~ /.*\/(.*)/;
    $self->{NAME} = $1;

    # the name of the element wiht Path("/") is "/"
    if( $self->{NAME} eq "" ) {
        $self->{NAME} = "/";
    }

    $self->{EID} = _resolve_eid($prof_dir, $ele_path);
    if( !defined($self->{EID}) ) {
        throw_error("failed to resolve element's ID", $ec->error);
        return();
    }
    if ( not _read_metadata($self) ) {
        throw_error("failed to read element's metadata", $ec->error);
        return();
    }

    if ( not _read_value($self) ) {
        throw_error("failed to read element's value", $ec->error);
        return();
    }

    bless($self, $class);
    return($self);

}


=item _get_tied_db()

Wrapper around EDG::WP4::CCM::DB::read() to attempt to cache the tied
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
    sub _get_tied_db($$) {
        my ($returnref, $path) = @_;
        my ($base) = $path =~ /(\w+)$/;
        if ($CACHE->{$base}->{err} or not $CACHE->{$base}->{path}
                        or $CACHE->{$base}->{path} ne $path) {
            my %newhash = ();
            $CACHE->{$base}->{path} = $path;
            # Should any old references be untied here?
            $CACHE->{$base}->{db} = \%newhash;
            $CACHE->{$base}->{err} = EDG::WP4::CCM::DB::read(\%newhash, $path);
        }
        $$returnref = $CACHE->{$base}->{db};
        return $CACHE->{$base}->{err};
    }
}

=item elementExists($config, $ele_path)

Returns true if the element identified by $ele_path exists
otherwise false is returned

=cut


sub elementExists {

    my $proto = shift;

    my ($config, $ele_path, $prof_dir);

    if (@_ != 2) {
        throw_error ("usage: Element->elementExists(config, ele_path)");
	return();
    }

    $config    = shift;		# profile's directory path
    $ele_path  = shift;		# element's configuration path

    if (UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $ele_path = $ele_path->toString();
    }
    $prof_dir  = $config->getConfigPath();
    my ($hashref, $eid);

    my $err = _get_tied_db(\$hashref, "${prof_dir}/path2eid");
    if ($err) {
        throw_error($err);
        return();
    }

    return (exists($hashref->{$ele_path}));
}

=pod

=item createElement($config, $ele_path)

Create a new Resource or Property object, depending on the type of
the element given by $ele_path. The $config parameter is a Configuration
object with the profile. The $ele_path parameter is the element's
configuration path (it can be either a Path object or a string).

=cut


sub createElement {

    my $proto = shift;

    my ($config, $ele_path, $prof_dir);
    my ($element, $ele_type);

    if (@_ != 2) {
        throw_error ("usage: Element->createElement(config, ele_path)");
	return();
    }

    $config    = shift;		# profile's directory path
    $ele_path  = shift;		# element's configuration path

    if (UNIVERSAL::isa($ele_path, "EDG::WP4::CCM::Path")) {
        $ele_path = $ele_path->toString();
    }

    $ele_type = _read_type($config, $ele_path);
    if (!$ele_type) {
        throw_error("Failed to read type of $ele_path", $ec->error);
        return ();
    }

    if( $ele_type & PROPERTY ) {
        $element = EDG::WP4::CCM::Property->new($config, $ele_path);
	unless($element){
	    throw_error ("Property->new($config, $ele_path)",$ec->error);
	    return();
	}
    } elsif ( $ele_type & RESOURCE ) {
        $element = EDG::WP4::CCM::Resource->new($config, $ele_path);
	unless($element){
	    throw_error ("Resource->new($config, $ele_path)",$ec->error);
	    return();
	}
    } else {
        throw_error("wrong element type $ele_path");
        return ();
    }

    return($element);

}

=item getConfiguration()


Returns the element's Configuration object

=cut

sub getConfiguration {

    my ($self) = shift;
    return $self->{CONFIG};

}

=item getEID()

Returns the Element ID of the object.

This method is not a part of the NVA-API specification, it may be a subject
to change.

=cut
sub getEID {

    my $self = shift;
    return($self->{EID});

}

=item getName()

Returns the name of the object

=cut
sub getName {

    my $self = shift;
    return($self->{NAME});

}

=item getUnescapedName()

Returns the name of the object, unescaped

=cut
sub getUnescapedName {
    my $self = shift;
    return unescape($self->getName());
}

=item getPath()

Returns a Path object with the element's path

=cut
sub getPath {

    my $self = shift;
    my $path;

    $path = EDG::WP4::CCM::Path->new($self->{PATH}->toString());

    return($path);

}

=item getType()

Returns the element's type, that is, one of the TYPE_* constans

=cut
sub getType {

    my $self = shift;
    return($self->{TYPE});

}

=item getDerivation()

Returns the element's derivation

=cut
sub getDerivation {

    my $self = shift;
    return($self->{DERIVATION});

}


=item getChecksum()

Returns the element's checksum (that is, MD5 digest)

=cut
sub getChecksum {

    my $self = shift;
    return($self->{CHECKSUM});

}

=item getDescription()

Returns the element's description

=cut
sub getDescription {

    my $self = shift;
    return($self->{DESCRIPTION});

}

=item getValue()

Returns the element's value, as a string

This method is not a part of the NVA-API specification, it may be a subject
to change.

=cut
sub getValue {

    my $self = shift;
    return($self->{VALUE});

}

=item isType($type)

Returns true if the element's type match type contained in argument $type

=cut
sub isType {

    my ($self, $type) = @_;
    return( ($type & $self->{TYPE}) == $type );

}

=item isResource()

Return true if the element's type is RESOURCE

=cut
sub isResource {

    my ($self, $type) = @_;
    return(RESOURCE & $self->{TYPE});

}

=item isProperty()

Return true if the element's type is PROPERTY

=cut
sub isProperty {

    my ($self, $type) = @_;
    return(PROPERTY & $self->{TYPE});

}

=item getTree

Returns a reference to a nested hash composed of all elements below
this element.  Corrected according to the III Quattor Workshop
recomendations. Now, PAN booleans map to Perl booleans, PAN lists map
to Perl array references and PAN nlists map to Perl hash references.

Note that links cannot be followed.



=cut

sub getTree
{
	my $self = shift;
	my ($ret, $el);

    SWITCH:
	{
		$self->isType(LIST) && do {
			$ret = [];
			while ($self->hasNextElement) {
		$el = $self->getNextElement();
	 			push (@$ret, $el->getTree);
			}
 			last SWITCH;
		};
		$self->isType(NLIST) && do {
			$ret = {};
			while ($self->hasNextElement) {
		$el = $self->getNextElement();
				$$ret{$el->getName()} = $el->getTree;
			}
			last SWITCH;
		};
		$self->isType(BOOLEAN) && do {
			$ret = $self->getValue eq 'true' ? 1:0;
			last SWITCH;
		};
		# Default clause
		$ret = $self->getValue;

		last SWITCH;
	};
	return $ret;
}


#
# _resolve_eid($prof_dir, $ele_path)
#
# Private function that resolve element's id number. $prof_dir is the profile
# full directory path, and $ele_path is the element path (as string)
#
sub _resolve_eid($$) {

    my ($prof_dir, $ele_path) = @_;
    my ($hashref, $eid);

    my $err = _get_tied_db(\$hashref, "${prof_dir}/path2eid");
    if ($err) {
        throw_error($err);
        return();
    }

    $eid = $hashref->{$ele_path};

    unless ($eid) {
	throw_error("cannot resolve element $ele_path");
	return();
    }

    return(unpack("L", $eid));

}

#
# _type_converter($string)
#
# Private function to convert a type in string format
# into a Type constant
# $string type in string format
#
sub _type_converter($) {

    my $type = shift;

    # type conversion
    # TODO: there must be a better way to do this ...
    return(STRING)  if ( $type eq "string" );
    return(DOUBLE)  if ( $type eq "double" );
    return(LONG)    if ( $type eq "long" );
    return(BOOLEAN) if ( $type eq "boolean" );
    return(LIST)    if ( $type eq "list" );
    return(NLIST)   if ( $type eq "nlist" );
    return(LINK)    if ( $type eq "link" );
    return(TABLE)   if ( $type eq "table" );
    return(RECORD)  if ( $type eq "record" );

    return(UNDEFINED);
}

#
# _read_metadata($self)
#
# Private function to read metadata information from DB file.
# $self if a reference to myself (Element) object
#
sub _read_metadata($) {

    my $self = shift;
    my ($prof_dir, $eid);
    my ($key, $hashref);

    $prof_dir = $self->{PROF_DIR};
    $eid      = $self->{EID};

    my $err = _get_tied_db(\$hashref, "${prof_dir}/eid2data");
    if ($err) {
        throw_error($err);
        return();
    }

    $key = pack("L", $eid | 0x10000000);
    $self->{TYPE} = $hashref->{$key};

    if( !defined($self->{TYPE}) ) {
        throw_error("failed to read element's type");
        return();
    }
    $self->{TYPE} = _type_converter($self->{TYPE});

    $key = pack("L", $eid | 0x20000000);
    $self->{DERIVATION} = $hashref->{$key};
    # TODO: metadata atribute "derivation" should not be optional
    if( !defined($self->{DERIVATION}) ) {
        $self->{DERIVATION} = "";
    }

    $key = pack("L", $eid | 0x30000000);
    $self->{CHECKSUM} = $hashref->{$key};
    if( !defined($self->{CHECKSUM}) ) {
        throw_error("failed to read element's checksum");
        return();
    }

    $key = pack("L", $eid | 0x40000000);
    $self->{DESCRIPTION} = $hashref->{$key};
    # metadata atribute "description" is optional
    if( !defined($self->{DESCRIPTION}) ) {
        $self->{DESCRIPTION} = "";
    }

    return(SUCCESS);

}

#
# _read_type($config, $ele_path)
#
# Private function to read Type information from DB file.
# You do not need an Element object to use this function.
# $config is a configuration profile
# $ele_path is the element path (as string)
#
sub _read_type($$) {

    my ($config, $ele_path);
    my ($prof_dir, $eid);
    my ($key, $hashref, $type);

    ($config, $ele_path) = @_;

    $prof_dir  = $config->getConfigPath();

    $eid = _resolve_eid($prof_dir, $ele_path);
    if( !defined($eid) ) {
        throw_error("failed to resolve element's ID", $ec->error);
        return();
    }

    my $err = _get_tied_db(\$hashref, "${prof_dir}/eid2data");
    if ($err) {
        throw_error($err);
        return();
    }

    $key = pack("L", $eid | 0x10000000);
    $type = $hashref->{$key};

    if( !defined($type) ) {
        throw_error("failed to read element's type");
        return();
    }

    $type = _type_converter($type);

    return($type);

}

#
# _read_value($self)
#
# Private function to read element's value from DB file.
# $self if a reference to myself (Element) object
#
sub _read_value ($$$) {

    my $self = shift;
    my ($prof_dir, $eid);
    my ($key, $hashref);

    $prof_dir = $self->{PROF_DIR};
    $eid      = $self->{EID};

    my $err = _get_tied_db(\$hashref, "${prof_dir}/eid2data");
    if ($err) {
        throw_error($err);
        return();
    }

    $key = pack("L", $eid);
    $self->{VALUE} = decode_utf8($hashref->{$key});
    if( !defined($self->{VALUE}) ) {
        throw_error("failed to read element's value");
        return();
    }

    return(SUCCESS);

}

1;	# so the require or use succeeds

__END__

=back

=head1 AUTHOR

Rafael A. Garcia Leiva <angel.leiva@uam.es>
Universidad Autonoma de Madrid

=head1 VERSION

${project.version}

=cut
