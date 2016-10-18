#${PMpre} EDG::WP4::CCM::SyncFile${PMpost}

use LC::Exception qw(SUCCESS throw_error);
use EDG::WP4::CCM::CCfg qw(getCfgValue);

use CAF::FileReader;
use CAF::FileWriter;

use parent qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(new read write);


=head1 NAME

EDG::WP4::CCM::SyncFile

=head1 SYNOPSIS

  $gl = SyncFile->new ("global.lock");
  $gl -> write ("yes");
  $locked  = $file -> read ();

=head1 DESCRIPTION

SyncFile module provides read/write access to
cid files and global.lock file.

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
{
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
{
    my ($self, $contents) = @_;
    my $fh = CAF::FileWriter->new($self->{"file_name"});
    print $fh "$contents\n";
    $fh->close();
    return SUCCESS;
}


=item get_file_name ()

get file name

=cut

sub get_file_name
{
    my ($self) = @_;
    return $self->{"file_name"};
}

=item new

create new SyncFile object where $file_name is the name of the sync
file

=cut

sub new
{
    my ($class, $file_name) = @_;
    my $self = {
        "file_name" => $file_name,
    };
    bless($self, $class);
    return $self;
}

=pod

=back

=cut

1;
