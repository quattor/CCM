# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::Path;

use strict;
use LC::Exception qw(SUCCESS throw_error);
use parent qw(Exporter);

our @EXPORT    = qw();
our @EXPORT_OK = qw();
our $VERSION = '${project.version}';

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

#TODO: work on exception messages


# ------------------------------------------------------

my $ec = LC::Exception::Context->new->will_store_errors;

=item new ($path)

create new object of Path type. Empty string is not
allowed as an input parameter. If input parameter is not specified,
Path is initialized to the root path ("/").

$path is a string representation of the path as defined in the NVA-API
Specification document

=cut

sub new {
  my ($class, $path) = @_;
  unless (defined ($path)) {
    $path = "/";
  }
  unless ($path=~/^\// && !($path=~/^(\/(\/)+)/)) {
    throw_error ("path must be an absolute path");
    return();
  }
  $path=~s/^\///;
  $path=~s/\/$//;
  my @s = split (/\//, $path);
  my $self = \@s;
  bless ($self, $class);
  return $self;
}

=item toString ()

get the string representation of path

=cut

sub toString {
  my ($self) = @_;
  my $path ="";
  if (@$self == 0) {
    $path = "/";
  } else {
    foreach my $ch (@$self) {
      $path = "$path/$ch";
    }
  }
  return $path;
}

=item up ()

removes last chunk of the path and returns it.
if the path is already "/" then then methods
rises an exception

=cut

sub up {
  my ($self) = @_;
  if (@$self == 0) {
    throw_error ("could not go up, it will generate empty path");
    return ()
  }
  return pop (@$self);
}

=item down ($chunk)

add one chunk to a path, chunk cannot be compound path
(it cannot contain "/" or be empty)

=cut

sub down {
  my ($self, $chunk) = @_;
  if ($chunk=~/\// || $chunk eq "") {
    throw_error ("input is not a simple path chunk");
    return();
  }
  push (@$self, $chunk);
  return $self;
}

# ------------------------------------------------------

1;

__END__

=back

=head1 AUTHOR

Piotr Poznanski <Piotr.Poznanski@cern.ch>

=head1 VERSION

$Id: Path.pm.cin,v 1.1 2005/01/26 10:09:51 gcancio Exp $

=cut
