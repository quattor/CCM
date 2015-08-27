# ${license-info}
# ${developer-info}
# ${author-info}

package EDG::WP4::CCM::Fetch::Unused;

=head1 NAME

EDG::WP4::CCM::Fetch::Unused

=head1 DESCRIPTION

Module provides unused methods. Can be removed later.

=head1 Functions

=over

=cut

use strict;
use warnings;

use CAF::Lock qw(FORCE_IF_STALE);

use constant DEFAULT_GET_TIMEOUT => 30;


sub RequestLock ($)
{

    # Try to get a lock; return lock object if successful.

    my ($lock) = @_;

    my $obj = CAF::Lock->new($lock);

    # try once to grab the lock, allow stealing if the lock is stale
    # we consider a lock to be stale if it's 5 mins old.
    if ($obj->set_lock(0, 0, CAF::Lock::FORCE_IF_STALE, 300)) {
        return $obj;
    }
    return undef;
}

sub ReleaseLock ($$)
{

    # Release lock on given object (filename for diagnostics).
    my ($self, $obj, $lock) = @_;
    $self->debug(5, "ReleaseLock: releasing: $lock");
    $obj->unlock();
}

sub FilesDiffer ($$)
{

    # Return 1 if they differ, 0 if the same.

    my ($fn1, $fn2) = @_;

    # ensure names are defined and exist
    return 1 if (!(defined($fn1) && -e "$fn1" && defined($fn2) && -e "$fn2"));
    my $fh1 = CAF::FileReader->new($fn1);
    my $fh2 = CAF::FileReader->new($fn2);
    my $differ = "$fh1" ne "$fh2";
    $fh1->close();
    $fh2->close();
    return $differ;
}


=pod

=back

=cut

1;
