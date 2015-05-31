# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::App::Options;

use strict;
use warnings;

use CAF::Application qw($OPTION_CFGFILE);
use CAF::Reporter;
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN setCfgValue);

our @ISA = qw(CAF::Application CAF::Reporter);

=head1 NAME

EDG::WP4::CCM::App::Options

=head1 DESCRIPTION

Use this module to create (commandline) application that interact with CCM directly.

Available convenience methods:

=over

=cut


# initialize
sub _initialize {

    my $self = shift;

    # version and usage
    $self->{'VERSION'} = "${project.version}";
    $self->{'USAGE'}   = sprintf("Usage: %s [OPTIONS...]", $0);

    # initialise
    unless ($self->SUPER::_initialize(@_)) {
        return undef;
    }

    return SUCCESS;
}

=item app_options

Return list of CCM application specific options and
commandline options for all CCM config options

=cut

sub app_options {

    my @options = (
        {
            # the ccm client will use the main ccm.conf from CCfg
            NAME    => "$OPTION_CFGFILE=s",
            DEFAULT => $CONFIG_FN,
            HELP    => 'configuration file for CCM',
        },

        {
            NAME    => "cid=s",
            HELP    => "set configuration CID (default 'undef' is the current CID; see CCM::CacheManager getCid for special values)",
        },

    );

    # Add support for all CCfg CONFIG_OPTIONS
    foreach my $opt (@CONFIG_OPTIONS) {
        # don't modify the original hasrefs
        my $newopt = {
            NAME => $opt->{option},
            HELP => $opt->{HELP},
        };

        $newopt->{NAME} .= $opt->{suffix} if exists($opt->{suffix});
        $newopt->{DEFAULT} .= $opt->{DEFAULT} if exists($opt->{DEFAULT});

        push(@options, $newopt);
    }

    return \@options;
}


=item setCCMConfig

Set the CCM Configuration instance for CID C<cid> under CCM_CONFIG attribute
using CacheManager's C<getConfiguration> method.

A CacheManager instance under CACHEMGR attribute is created if none exists
or C<force_cache> is set to true.

Returns SUCCESS on success, undef on failure.

=cut

sub setCCMConfig
{
    my ($self, $cid, $force_cache) = @_;

    if((! defined($self->{CACHEMGR})) || $force_cache) {
        my $configfile = $self->option($OPTION_CFGFILE);
        my $cacheroot = $self->option('cache_root');

        # The CCM::CacheManager->new() does CCfg::initCfg
        # but we need to pass/redefine the relevant commandline options too.
        # TODO: what a mess
        # TODO: is there a way to only set the values defined on commandline?
        foreach my $opt (@CONFIG_OPTIONS) {
            my $option = $opt->{option};
            # force them to protect against (re)reading (e.g. in Fetch)
            setCfgValue($option, $self->option($option), 1);
        }

        my $msg = "cache manager with cacheroot $cacheroot and configfile $configfile";
        $self->verbose("Accessing CCM $msg.");
        $self->{CACHEMGR} = EDG::WP4::CCM::CacheManager->new($cacheroot, $configfile);
        unless (defined $self->{'CACHEMGR'}) {
            throw_error ("Cannot access $msg.");
            return;
        }
    }

    $msg = "for CID ". (defined($cid) ? $cid : "<undef>");
    $self->verbose("getting CCM configuration $msg.");
    $self->{CCM_CONFIG} = $self->{CACHEMGR}->getConfiguration(undef, $cid);
    unless (defined $self->{CCM_CONFIG}) {
        throw_error ("Cannot get configuration via CCM $msg.");
        return;
    }

    return SUCCESS;
}

=item getCCMConfig

returns the CCM configuration instance

=cut

sub getCCMConfig {
    my $self = shift;
    return $self->{CCM_CONFIG};
}

=pod

=back

=cut


1;
