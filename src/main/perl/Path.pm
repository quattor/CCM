# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::Path;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw();
our $VERSION   = '${project.version}';

use overload '""' => 'toString';

=head1 NAME

EDG::WP4::CCM::Path - Path class

=head1 SYNOPSIS

 $path = Path->new(["/hardware/memory/size"]);
 $string = $path->toString();
 $path = $path->down($string);
 $path = $path->up();

=head1 DESCRIPTION

Module provides implementation of the Path class. Class is used
to manipulate absolute paths

=over

=cut

my $ec = LC::Exception::Context->new->will_store_errors;

=item new ($path)

create new object of Path type. Empty string is not
allowed as an input parameter. If input parameter is not specified,
Path is initialized to the root path ("/").

$path is a string representation of the path as defined in the NVA-API
Specification document

=cut

sub new
{
    my ($class, $path) = @_;
    unless (defined($path)) {
        $path = "/";
    }

    my @s = split('/', $path, -1);
    my $start = shift @s;

    # remove trailing /
    my $end = pop @s;
    push(@s, $end) if (defined($end) && $end ne '');

    # must start with /, but not with //+
    unless (defined($start) && $start eq '' && (!@s || $s[0] ne '')) {
        throw_error("path $path must be an absolute path: start '"
                . ($start || '')
                . "', remainder "
                . join(' / ', @s));
        return ();
    }

    my $self = \@s;
    bless($self, $class);
    return $self;
}

=item toString ()

get the string representation of path

=cut

sub toString
{
    my ($self) = @_;
    return "/" . join('/', @$self);
}

=item up ()

removes last chunk of the path and returns it.
if the path is already "/" then then methods
rises an exception

=cut

sub up
{
    my ($self) = @_;
    if (@$self == 0) {
        throw_error("could not go up, it will generate empty path");
        return ();
    }
    return pop(@$self);
}

=item down ($chunk)

add one chunk to a path, chunk cannot be compound path
(it cannot contain "/" or be empty)

=cut

sub down
{
    my ($self, $chunk) = @_;
    if ($chunk =~ /\// || $chunk eq "") {
        throw_error("input is not a simple path chunk");
        return ();
    }
    push(@$self, $chunk);
    return $self;
}

=item merge (@subpaths)

Return a new instance with optional subpaths added

=cut


sub merge
{

    my ($self, @subpaths) = @_;

    my $newpath = EDG::WP4::CCM::Path->new("$self");
    foreach my $subpath (@subpaths) {
        $newpath->down($subpath);
    }
    return $newpath
}


=pod

=back

=cut

1;
