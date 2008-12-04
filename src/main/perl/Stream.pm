# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::Stream;

use strict;
use LC::Exception qw(SUCCESS throw_error);

BEGIN{
 use      Exporter;
 use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

 @ISA       = qw(Exporter);
 @EXPORT    = qw();
 @EXPORT_OK = qw(new read write);
 $VERSION   = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);
}

=head1 NAME

EDG::WP4::CCM::Stream - Stream class

=head1 SYNOPSIS
 
 $stream = Stream->new($cm, $url);
 $buf_size = $stream->setBufSize($buf_size);
 $buf = $stream->getBlock();
 $boolean = $stream->isClosed ();

=head1 DESCRIPTION

The class Stream helps the user to read large files using a stream
of data. The user can control the blok size as well.

=over

=cut

# ------------------------------------------------------

my $ec = LC::Exception::Context->new->will_store_errors;

#
# new ($cm, $url)
#
# Create new Stream object. The $cm parameter is a CacheManager
# Manager object where to cache the file. The $url parameter is the URL
# address of the file to stream.
#
sub new ($$) {

    my $proto = shift;
    my $class = ref($proto) || $proto;
    my ($cm, $url);
    my $self = {};

    if (@_ != 2) {
        throw_error ("usage: Stream->new(CacheManager, URL)");
	return();
    }

    $cm = shift;
    if (!UNIVERSAL::isa($cm, "EDG::WP4::CCM::CacheManager")) {
        throw_error ("usage: Stream->new(CacheManager, URL)");
	return();
    }

    $url = shift;

    my $fn = $cm->cacheFile($url);
    unless ($fn) {
        throw_error ("$cm->cacheFile($url)", $ec->error);
        return();
    }

    $self->{FILE_NAME}	= $fn;	# cached file name
    $self->{SYSBUFSIZE}	= 8192;	# default buff size
    $self->{OFFSET}	= 0;
    $self->{CLOSED}	= 0;

    bless ($self, $class);
    return $self;

}

=item setDefaultBufSize($buf_size)

Set the default buffer size to $buf_size

=cut
sub setDefaultBufSize {

    my($self, $size) = @_;
    $self->{SYSBUFSIZE} = $size;
    return($self->{SYSBUFSIZE});

}

=item getBlock([$buf_size])

Get a block of size $buf_size from file. If you do not specify a buffer
size, the default buffer size will be used.

=cut
sub getBlock {

    my($self) = shift;

    my($buff, $buff_size, $n_bytes);
    local(*FH);

    if (@_ == 1) {
        $buff_size = shift;
    } else {
        $buff_size = $self->{SYSBUFSIZE};	# use default buf. size
    }

    if ($self->{CLOSED}) {
	throw_error("file $self->{FILE_NAME} is closed");
	return();
    }

    unless (open(FH, "<" . $self->{FILE_NAME})) {
	throw_error("open($self->{FILE_NAME})", $!);
	return();
    }
    binmode(FH);

    $buff = "";
    $n_bytes = read(FH, $buff, $buff_size, $self->{OFFSET});
    unless (defined($n_bytes)) {
	throw_error("read($self->{FILE_NAME})", $!);
	return();
    }

    $self->{OFFSET} += $n_bytes;
    if( eof(FH) ) {
        $self->{CLOSED} = 1;
    }

    unless (close(FH)) {
	throw_error("close($self->{FILE_NAME})", $!);
	return();
    }

    return($buff);

}

=item isClosed ()

Return true if the stream has been closed

=cut
sub isClosed () {

    my ($self) = shift;
    return $self->{CLOSED};

}


# ------------------------------------------------------

1;

__END__


=back

=head1 AUTHOR

Piotr Poznanski <Piotr.Poznanski@cern.ch>
Rafael A. Garcia Leiva <angel.leiva@uam.es>

=head1 VERSION

$Id: Stream.pm.cin,v 1.1 2005/01/26 10:09:52 gcancio Exp $

=cut

