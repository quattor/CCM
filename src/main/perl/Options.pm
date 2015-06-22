# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package EDG::WP4::CCM::Options;

use strict;
use warnings;

use CAF::Application qw($OPTION_CFGFILE);
use CAF::Reporter;
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN setCfgValue);
use EDG::WP4::CCM::Element qw(escape);
use Readonly;

our @ISA = qw(CAF::Application CAF::Reporter);

Readonly::Hash my %PATH_SELECTION_METHODS => {
    profpath => {
        help => 'profile path',
        method => sub { return $_[0]; },
    },
    component => {
        help => 'component',
        method => sub { return "/software/components/". $_[0]; },
    },
    metaconfig => {
        help => 'metaconfig service',
        method => sub { return "/software/components/metaconfig/services/". escape($_[0]) . "/contents"; },
    },
};

Readonly::Hash my %ACTIONS => {
    showcids => 'Show valid CIDs',
};

=head1 NAME

EDG::WP4::CCM::Options

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

    # Actions
    foreach my $act (sort keys %ACTIONS) {
        push(@options, {
             NAME => "$act",
             HELP => $PATH_SELECTION_METHODS{$act},
             });
    }

    # profile path selection options
    foreach my $sel (sort keys %PATH_SELECTION_METHODS) {
        push(@options, {
             NAME => "$sel=s@",
             HELP => "Select the ".$PATH_SELECTION_METHODS{$sel}->{help}."(s)",
             });
    }

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

If C<cid> is not defined, the C<cid> value from the C<--cid>-option will be used.
(To use the current CID when another cid value set via C<--cid>-option, pass an empty
string or the string 'current').

A CacheManager instance under CACHEMGR attribute is created if none exists
or C<force_cache> is set to true.

Returns SUCCESS on success, undef on failure.

=cut

sub setCCMConfig
{
    my ($self, $cid, $force_cache) = @_;

    my $msg;

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

        $msg = "cache manager with cacheroot $cacheroot and configfile $configfile";
        $self->verbose("Accessing CCM $msg.");
        $self->{CACHEMGR} = EDG::WP4::CCM::CacheManager->new($cacheroot, $configfile);
        unless (defined $self->{'CACHEMGR'}) {
            throw_error ("Cannot access $msg.");
            return;
        }
    }

    $cid = $self->option('cid') if(! defined($cid));

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

sub getCCMConfig
{
    my $self = shift;
    return $self->{CCM_CONFIG};
}

=item gatherPaths

Retrun arrayref of selected profile path (via the PATH_SELECTION_METHODS)

=cut

sub gatherPaths
{
    my $self = shift;

    my @paths;
    # profile path selection options
    foreach my $sel (sort keys %PATH_SELECTION_METHODS) {
        my $values = $self->option($sel);
        my $method = $PATH_SELECTION_METHODS{$sel}->{method};
        if (defined($values)) {
            foreach my $val (@$values) {
                push(@paths, $method->($val))
            }
        }
    }
    return \@paths;
}

# wrapper around print (for easy unittesting)
sub _print
{
    my ($self, @args) = @_;
    print @_;
}

=item action_showcids

the showcids action prints all sorted profile CIDs as comma-separated list

=cut

sub action_showcids
{
    my $self = shift;

    $self->setCCMConfig();

    my $cids = $self->{CACHEMGR}->getCids();

    $self->_print(join(',', @$cids), "\n");

    return SUCCESS;
}

=item action

Run first of the predefined actions via the action_<actionname> methods

=cut

sub action
{
    my $self = shift;

    # defined actions
    my @acts = map {$_ if $self->option($_)} sort keys %ACTIONS;
    my $act;

    # very primitive for now: run first found
    if (@acts && $acts[0] =~ m/^(\w+)$/) {
        $act = $1;
    }

    if ($act) {
        my $method = $self->can("action_$act");
        return if(! $method);

        # execute it
        return $method->($self);
    }

    # return SUCCESS if no actions selected (nothing goes wrong)
    return SUCCESS;
}

=pod

=back

=cut


1;
