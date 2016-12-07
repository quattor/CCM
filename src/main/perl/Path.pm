#${PMpre} EDG::WP4::CCM::Path${PMpost}

use parent qw(Exporter);
our @EXPORT    = qw(unescape);
our @EXPORT_OK = qw(escape set_safe_unescape reset_safe_unescape);

use Readonly;
use LC::Exception qw(SUCCESS throw_error);

our $ec = LC::Exception::Context->new->will_store_errors;

use overload '""' => '_stringify', 'bool' => '_boolean';

# Default safe_unescape list
Readonly::Array our @SAFE_UNESCAPE => (
    '/software/components/download/files/',
    '/software/components/filecopy/services/',
    '/software/components/metaconfig/services/',
    '/software/packages/',
    qr{/software/packages/[^/]+/}, # software package names should have no / in their name
);

# This is a module variable and can be set with C<set_safe_unescape>
# and emptied with C<reset_safe_unescape> exported functions.
# See C<set_safe_unescape> function for more explanation.
# All paths end with trailing /, via set_safe_unescape.
my @safe_unescape;

# An arrayref, when defined, C<reset_safe_unescape> will set
# @safe_unescape using C<set_safe_unescape> using this value.
# Mainly for unittesting purposes.
our $_safe_unescape_restore;

=head1 NAME

EDG::WP4::CCM::Path - Path class

=head1 SYNOPSIS

    $path = EDG::WP4::CCM::Path->new("/hardware/memory/size");
    print "$path"; # stringification

    $path = $path->down($level);

    $path = $path->up();

=head1 DESCRIPTION

Module provides implementation of the Path class. Class is used
to manipulate absolute paths

=head2 Public methods

=over

=item new ($path)

Create new C<EDG::WP4::CCM::Path> instance.

If C<path> argument is not specified, root path (C</>) is used.
Empty string is not allowed as an argument.

C<path> is a string representation of the path as defined in the NVA-API
Specification document.

=cut

sub new
{
    my ($class, $path) = @_;
    unless (defined($path)) {
        $path = "/";
    }

    my @s = path_split($path);
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

=item depth

Return the number of subpaths, starting from C</>.

=cut

sub depth
{
    my $self = shift;
    return scalar @$self;
}

=item get_last

Return last (safe unescaped) subpath or undef in case of C</>.
The C<strip_unescape> boolean is passed to C<_safe_unescape>.

=cut

# Do not use 'last' as method name (last is a list/array TT VMethod)
sub get_last
{
    my ($self, $strip_unescape) = @_;

    my $last;

    # if parent exists, it implies self->depth > 0,
    # so we can use [-1] safely
    my $parent = $self->parent();
    if ($parent) {
        $last = _safe_unescape($parent, @{$self}[-1], $strip_unescape);
    }

    return $last;
}

=item toString

Get the (raw) string representation of path.

The C<EDG::WP4::CCM::Path> instances also support stringification
(the C<_stringify> method is used for that) and might create different result
due to C<safe_unescape>.

=cut

# This method is used for creating and reading the configuration databases
# and should not be modified without making changes in Element and Configuration

sub toString
{
    my ($self) = @_;

    return "/" . join("/", @$self);
};

=item _boolean

bool overload: C<Path> instance is always true (avoids stringification on logic test)

=cut

# stringification on logic test is known to cause problems with safe_unescape

sub _boolean
{
    return 1;
}

=item _stringify

Method for overloaded stringification.

This includes support for C<safe_unescape> to wrap
unescaped subpaths in C<{}>.

=cut

sub _stringify
{
    my ($self) = @_;

    my $txt;

    if(@safe_unescape && $self->depth()) {
        $txt = "/";
        # Slow
        foreach my $subpath (@$self) {
            $txt .= _safe_unescape($txt, $subpath) . "/";
        };
        # Remove trailing /
        chop($txt);
    } else {
        $txt = $self->toString();
    }

    return $txt;
}

=item up

Removes last chunk of the path and returns it.
If the path is already C</> then the method
raises an exception.

=cut

sub up
{
    my ($self) = @_;

    if ($self->depth()) {
        return pop(@$self);
    } else {
        throw_error("could not go up, it will generate empty path");
        return ();
    }
}

=item down

Add C<chunk> to the path. The chunk can be compound path.
(A leading C</> will be ignored).

=cut

sub down
{
    my ($self, $chunk) = @_;

    my @chunks = path_split($chunk);
    push(@$self, grep {defined($_) && $_ ne ''} @chunks);

    return $self;
}

=item merge

Return a new instance with optional (list of) subpaths added.

=cut

# merge is the name of similar TT VMethod for list/array
# (and in TT it also returns a new instance)

sub merge
{

    my ($self, @subpaths) = @_;

    my $newpath = EDG::WP4::CCM::Path->new("$self");
    foreach my $subpath (@subpaths) {
        $newpath->down($subpath);
    }
    return $newpath
}

=item parent

Return a new instance with parent path.
Returns undef if current element is C</>.

=cut


sub parent
{

    my ($self) = @_;

    my $parent;
    if ($self->depth()) {
        $parent = EDG::WP4::CCM::Path->new("$self");
        $parent->up();
    }

    return $parent;
}

=back

=head2 Public functions

=over

=item unescape

Returns an unescaped version of the argument. This method is exported
for use with all the components that deal with escaped keys.

=cut

sub unescape
{
    my $str = shift;

    $str =~ s!(_[0-9a-f]{2})!sprintf ("%c", hex($1))!eg;
    return $str;
}

=item escape

Returns an escaped version of the argument.  This method is exported on
demand for use with all tools that have to escape and unescape values.

=cut

sub escape
{
    my $str = shift;

    $str =~ s/(^[0-9]|[^a-zA-Z0-9])/sprintf("_%lx", ord($1))/eg;
    return $str;
}

=item path_split

Function to split a string in list of subpaths.
Supports escaping of subpaths wrapped in C<{...}>.

=cut

sub path_split
{
    my $path = shift;

    # First handle escape {} string
    # use -1, make sure no trailing empty strings are removed
    # Use postive lookahead, not a match for trailing /|$
    my @to_esc = split(/(\/|^)\{(.+?)\}(?=(?:\/|$))/, $path, -1);
    # Handle empty string path
    # Splitting an empty string always returns an empty list
    push(@to_esc, '') if ! @to_esc;

    # This is an array with odd number of elements <val>[<sep><val>[<sep><val>[...]]]
    # <sep> is the matching group of the split pattern
    # Shift first element (initial <val>)
    my $esc_path = shift(@to_esc);

    while (@to_esc) {
        # First 2 are the matched groups that make up <sep>
        #   The second group must be escaped
        # 3rd is the <val>
        $esc_path .= join('', shift(@to_esc), escape(shift(@to_esc)), shift(@to_esc));
    }

    return split('/', $esc_path, -1);
}

=item set_safe_unescape

Set the list of (parent) paths whose children are known to be escaped paths.
(The list is set to all arguments passed, not appended to current safe_unescape list).

Paths can either be strings (an exact match will be used)
or compiled regular expressions.

These child subpaths are safe to represent as their unescaped value
wrapped in C<{}> when <toString> method is called (e.g. during stringification).

Parent paths who have a safe-to escape parent path of their own should be added
already escaped.

The list is stored in the C<safe_unescape> module variable and
can emptied with C<reset_safe_unescape> exported functions.

If no argument is passed, a predefined list of paths is used. The paths are known
to be escaped in quattor profiles, e.g. C</software/components/metaconfig/services>.
(To reset the active C<safe_unescape> list, use C<reset_safe_unescape> function.

=cut

sub set_safe_unescape
{
    my @paths = @_;

    @paths = @SAFE_UNESCAPE if ! @paths;

    @safe_unescape = ();
    foreach my $path (@paths) {
        if (ref($path) eq '') {
            $path =~ s/\/*$/\//;
        }
        push(@safe_unescape, $path);
    }
}

=item reset_safe_unescape

Reset the C<safe_unescape> list.

=cut

sub reset_safe_unescape
{
    if ($_safe_unescape_restore) {
        set_safe_unescape(@$_safe_unescape_restore);
    } else {
        @safe_unescape = ();
    };
}

=item _safe_unescape

Given C<path> and C<subpath>, test is C<path> is in C<@safe_unescape>
and if it is, return unescaped subpath enclosed in C<{}> (or not enclosed if
C<strip_unescape> is true).

If not, return unmodified subpath.

=cut

sub _safe_unescape
{
    my ($path, $subpath, $strip_unescape) = @_;

    # stringification of $path in case it is a Path instance
    $path = "$path";
    # Add trailing /, same as @safe_unescape.
    $path =~ s/\/*$/\//;

    # Slow
    if (grep {(ref($_) eq 'Regexp') ? ($path =~ $_) : ($path eq $_)} @safe_unescape) {
        my $unescaped = unescape($subpath);
        if ($unescaped ne $subpath) {
            $subpath = $strip_unescape ? $unescaped : "{$unescaped}";
        };
    };

    return $subpath;
}


=pod

=back

=cut

1;
