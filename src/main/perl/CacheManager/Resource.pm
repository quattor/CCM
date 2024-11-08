#${PMpre} EDG::WP4::CCM::CacheManager::Resource${PMpost}

use LC::Exception qw(SUCCESS throw_error);
use parent qw(EDG::WP4::CCM::CacheManager::Element);

my $ec = LC::Exception::Context->new->will_store_errors;

=head1 NAME

EDG::WP4::CCM::CacheManager::Resource - Resource class

=head1 SYNOPSIS

 %hash = $resource->getHash();
 @list = $resource->getList();
 $boolean = $resource->hasNextElement();
 [$property | $resource] = $resource->getNextElement();
 [$property | $resource] = $resource->getCurrentElement();
 $resource->reset();

=head1 DESCRIPTION

The class Resource is a derived class of Element class, and implements
methods that are specific to Resources, that is, internal nodes of
the configuration tree, containing other resources and properties.
tree.

=over

=cut

=item new($config, $res_path)

Create new Resource object. The $config parameter is a Configuration
object with the profile. The $res_path parameter is the resource's
configuration path.

=cut

sub new
{

    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);

    # check that element it is really a resource
    if (defined $self && !$self->isResource()) {
        throw_error("element is not of type Resource");
        return ();
    }

    # initialize list of elements
    $self->{ELEMENTS} = [split(/\x0/, $self->{VALUE})];

    $self->{CURRENT} = -1;

    bless($self, $class);
    return $self;

}

=item getHash()

Return a hash of elements, indexed by name
The method raises an exception if the resource type is not nlist

This method is not a part of the NVA-API specification, it may be a
subject to change.

=cut

sub getHash
{

    my $self = shift;
    my (%hash, $path, $el_path, $ele, $i, $name);

    # check that the resource type is nlist
    if (!$self->isType($self->NLIST)) {
        throw_error("resource is not of type NLIST");
        return ();
    }

    # from the list of names $self->{ELEMENTS}
    # create a hash of Elements objects indexed by name

    $path = $self->{PATH}->toString();
    for ($i = 0; $i <= ($#{$self->{ELEMENTS}}); $i++) {
        $name = $self->{ELEMENTS}[$i];
        if ($path eq "/") {
            $el_path = $path . $name;
        } else {
            $el_path = $path . "/" . $name;
        }
        $ele = EDG::WP4::CCM::CacheManager::Element->createElement($self->{CONFIG}, $el_path);
        unless ($ele) {
            throw_error("failed to create element $el_path)", $ec->error);
            return ();
        }
        $hash{$name} = $ele;
    }

    return (%hash);

}

=item getList()

Return an array of elements. The method raises an exception
if the resource type is not list.

This method is not a part of the NVA-API specification, it may be a
subject to change.

=cut

sub getList
{

    my $self = shift;
    my (@array, $path, $el_path, $ele, $i);

    # check that the resource type is list
    if (!$self->isType($self->LIST)) {
        throw_error("resource is not of type LIST");
        return ();
    }

    # from the list of names $self->{ELEMENTS}
    # create an array of Elements objects

    $path = $self->{PATH}->toString();
    for ($i = 0; $i <= ($#{$self->{ELEMENTS}}); $i++) {
        if ($path eq "/") {
            $el_path = $path . $i;
        } else {
            $el_path = $path . "/" . $i;
        }
        $ele = EDG::WP4::CCM::CacheManager::Element->createElement($self->{CONFIG}, $el_path);
        unless ($ele) {
            throw_error("failed to create element $el_path", $ec->error);
            return ();
        }
        $array[$i] = $ele;
    }

    return (@array);

}

=item hasNextElement()

Return true if the iteration through Resource has
more elements, otherwise returns false

=cut

sub hasNextElement
{

    my $self = shift;

    if ($self->{CURRENT} < $#{$self->{ELEMENTS}}) {
        return (SUCCESS);
    }

    return ();

}

=item getNextElement()

Return the next element in the iteration

=cut

sub getNextElement
{

    my $self = shift;
    my $element;

    if (!$self->hasNextElement()) {
        throw_error("property has no more elements", $ec->error);
        return ();
    }
    $self->{CURRENT}++;
    $element = $self->getCurrentElement();

    return ($element);

}

=item getCurrentElement()

Return current element in the iteration. This is the element
that was returned by the last call of getNextElement()

=cut

sub getCurrentElement
{

    my $self = shift;
    my ($element, @elements, $path, $el_path);

    if ($self->{CURRENT} == -1) {
        throw_error("no current element available", $ec->error);
        return ();
    }

    $path = $self->{PATH}->toString();
    if ($path eq "/") {
        $el_path = $path . $self->{ELEMENTS}[$self->{CURRENT}];
    } else {
        $el_path = $path . "/" . $self->{ELEMENTS}[$self->{CURRENT}];
    }

    $element = EDG::WP4::CCM::CacheManager::Element->createElement($self->{CONFIG}, $el_path);
    unless ($element) {
        throw_error("failed to create element $el_path", $ec->error);
        return ();
    }

    return $element;

}

=item reset()

Reset the iteration. After this operation being called,
getNextElement() will return first element in the iteration

=cut

sub reset
{

    my $self = shift;

    $self->{CURRENT} = -1;

    return (SUCCESS);

}

=pod

=back

=cut

1;
