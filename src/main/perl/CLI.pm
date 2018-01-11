#${PMpre} EDG::WP4::CCM::CLI${PMpost}

use parent qw(EDG::WP4::CCM::Options);
use CAF::Object qw(SUCCESS);
use EDG::WP4::CCM::CacheManager::DB qw(read_db close_db);
use EDG::WP4::CCM::CacheManager::Encode qw(encode_eids decode_eid $PATH2EID $EID2DATA @EIDS_PACK);
use EDG::WP4::CCM::TextRender qw(ccm_format @CCM_FORMATS);
use EDG::WP4::CCM::Path qw(set_safe_unescape reset_safe_unescape);
use Readonly;

Readonly::Hash my %CLI_ACTIONS => {
    show => 'Print the tree starting from the selected path.',
    dumpdb => 'Print path2eid and eid2path DBs.',
};

Readonly my $DEFAULT_ACTION => 'show';

=head1 NAME

EDG::WP4::CCM::CLI

=head1 DESCRIPTION

This module inplements the CCM CLI. The final script should be rather minimal,
and a module allows for far easier unittesting.

=cut

sub _initialize {

    my ($self, $cmd, @args) = @_;

    my $argsref = \@args;

    $self->add_actions(\%CLI_ACTIONS);

    $self->default_action($DEFAULT_ACTION);

    my $res = $self->SUPER::_initialize($cmd, $argsref);

    # Final arguments are all profpaths
    if (@$argsref) {
        $self->{profpaths} = $argsref;
        $self->debug(2, "Add non-option cmdline profpaths: ", join(',', @{$self->{profpaths}}));
    } else {
        $self->{profpaths} = [];
        $self->debug(2, "No non-option cmdline profpaths");
    };

    return $res;
}

# extend the CCM::Options
sub app_options
{
    my $self = shift;

    my $opts = $self->SUPER::app_options(@_);

    push(@$opts,
         {
             NAME => 'format=s',
             DEFAULT => 'query',
             HELP => 'Select the format (avail: ' . join(', ', @CCM_FORMATS). ')',
         },
    );

    return $opts;
}

=pod

=over

=item action_show

Print the tree starting from the selected path(s). Not existing paths are skipped.

=cut

sub action_show
{
    my $self = shift;

    my $cfg = $self->getCCMConfig();
    return if (! defined($cfg));

    set_safe_unescape();

    foreach my $path (@{$self->gatherPaths(@{$self->{profpaths}})}) {
        if(! $cfg->elementExists($path)) {
            $self->debug(4, "action_show: no element for path $path");
            next;
        }

        my $trd = ccm_format(
            $self->option('format'),
            $cfg->getElement($path),
            );
        if(! defined($trd)) {
            $self->debug(3, "action_show: invalid format ", $self->option('format'));
            return;
        }

        my $fmt_txt = $trd->get_text();

        # TODO: no fail on renderfailure?
        if(defined($fmt_txt)) {
            $self->_print($fmt_txt);
        } else {
            $self->debug(3, "action_show: Renderfailure for path $path",
                         " and format ", $self->option('format'),
                         ": ", $trd->{fail});
            return;
        };
    }

    reset_safe_unescape();

    return SUCCESS;
}


=item action_dumpdb

Lowlevel debugging function to dump the profile DBs
C<path2eid> and C<eid2data>.

=cut

sub action_dumpdb
{
    my $self = shift;

    my $cfg = $self->getCCMConfig();
    return if (! defined($cfg));

    my $prof_dir = $cfg->getConfigPath();

    my (%path2eid, %eid2data);

    foreach my $db ([$PATH2EID, \%path2eid],
                    [$EID2DATA, \%eid2data]) {
        my $err = read_db($db->[1], "$prof_dir/$db->[0]");
        if ($err) {
            $self->error("could not read $prof_dir/$db->[0]: $err\n");
            close_db("$prof_dir/$PATH2EID");
            close_db("$prof_dir/$EID2DATA");
            return;
        }
    };

    $self->_print("$PATH2EID:\n");
    foreach my $path (sort keys %path2eid) {
        $self->_print("$path => ", sprintf("%x", decode_eid($path2eid{$path})), "\n");
    }

    $self->_print("$EID2DATA:\n");
    foreach my $enc_eid (sort keys %eid2data) {
        $self->_print(sprintf("%x", decode_eid($enc_eid)), " => ", $eid2data{$enc_eid}, "\n");
    }

    $self->_print("\n$PATH2EID and $EID2DATA combined:\n");
    foreach my $path (sort keys %path2eid) {
        my $eid = decode_eid($path2eid{$path});
        my $eids = encode_eids($eid);

        $self->_print("$path ($eid) =>\n");
        foreach my $type (@EIDS_PACK) {
            my $value = $eid2data{$eids->{$type}};
            $self->_print(' ' x 2, substr($type, 0, 1), ": ", defined($value) ? $value : '<undef>', "\n");
        };
    }

    close_db("$prof_dir/$PATH2EID");
    close_db("$prof_dir/$EID2DATA");

    return SUCCESS;
}

=pod

=back

=cut


1;
