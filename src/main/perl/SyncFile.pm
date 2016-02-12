# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package      EDG::WP4::CCM::SyncFile;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::CCfg qw(getCfgValue);

use CAF::FileReader;
use CAF::FileWriter;

use parent qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(new read write);
our $VERSION   = '${project.version}';

=head1 NAME

EDG::WP4::CCM::SyncFile

=head1 SYNOPSIS

  $gl = SyncFile->new ("global.lock");
  $gl -> write ("yes");
  $locked  = $file -> read ();

=head1 DESCRIPTION

SyncFile module provides synchronised (exclusive) read/write access to
cid files and global.lock file. It uses flock (2).

flock non blocking call is used for acquiring the lock in lock
acquiring subroutine. The subroutine retries several times if lock
cannot be acquired. If after retries lock is still not acquired, error
is reported.


=over

=cut

my $ec = LC::Exception::Context->new->will_store_errors;

=item read ()

read contents of the file. It reads the first line of the file and
removes \n.  If the contents of file does not contain "/n" at the end,
function behaviour is not guaranteed, most likely it chop last
character.

=cut

sub read
{    #T
    my ($self) = @_;
    my $fh = CAF::FileReader->new($self->{"file_name"});
    chop($fh);
    return "$fh";
}

=item write ($contents)

remove and write contents of the file. It adds \n at the and of the
contents.

=cut

sub write
{    #T
    my ($self, $contents) = @_;
    my $fh = CAF::FileWriter->new($self->{"file_name"});
    print $fh "$contents\n";
    $fh->close();
    return SUCCESS;
}

#
# lock using blocking flock call
#

sub _block
{
    unless (flock(FH, 2)) {
        throw_error("flock (FH, 2)", $!);
        return ();
    }
    return SUCCESS;
}

#
# lock using unblocking call with timeout mechanism
#

sub _lock
{
    my ($self) = @_;
    my $locked = flock(FH, 6);
    my $i = 1;
    $locked = flock(FH, 6);
    while (!$locked && $i++ < $self->{"retries"}) {
        sleep($self->{"wait"});
        $locked = flock(FH, 6);
    }
    unless ($locked) {
        throw_error("could not get lock (flock (FH, 6))", $!);
        return ();
    }
    return SUCCESS;
}

#
# unlock using flock call
#

sub _unlock
{
    unless (flock(FH, 8)) {
        throw_error("flock (FH, 8)", $!);
        return ();
    }
    return SUCCESS;
}

=item get_file_name ()

get file name

=cut

sub get_file_name
{    #T
    my ($self) = @_;
    return $self->{"file_name"};
}

=item new ($file_name)

create new SyncFile object where $file_name is the name of the sync
file

=cut

sub new
{    #T
    my ($class, $file_name, $wait, $retries) = @_;
    my $self = {
        "file_name" => $file_name,
        "wait"      => getCfgValue("lock_wait"),
        "retries"   => getCfgValue("retrieve_retries"),
    };
    bless($self, $class);
    return $self;
}

=pod

=back
=cut

1;
