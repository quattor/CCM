# -*- mode: Perl -*-

# Data::Compare - compare perl data structures
# Author: Fabien Tassin <fta@sofaraway.org>
# Copyright 1999-2001 Fabien Tassin <fta@sofaraway.org>

package Data::Compare;

use strict;
use vars qw(@ISA @EXPORT $VERSION $DEBUG);
use Exporter;
use Carp;

@ISA     = qw(Exporter);
@EXPORT  = qw(Compare);
$VERSION = 0.02;
$DEBUG   = 0;

sub Compare ($$);

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  bless $self, $class;
  $self->{'x'} = shift;
  $self->{'y'} = shift;
  return $self;
}

sub Cmp ($;$$) {
  my $self = shift;

  croak "Usage: DataCompareObj->Cmp(x, y)" unless $#_ == 1 || $#_ == -1;
  my $x = shift || $self->{'x'};
  my $y = shift || $self->{'y'};

  Compare($x, $y);
}

sub Compare ($$) {
  croak "Usage: Data::Compare::Compare(x, y)\n" unless $#_ == 1;
  my $x = shift;
  my $y = shift;

  my $refx = ref $x;
  my $refy = ref $y;

  unless ($refx || $refy) { # both are scalars
    return $x eq $y if defined $x && defined $y; # both are defined
    !(defined $x || defined $y);
  }
  elsif ($refx ne $refy) { # not the same type
    0;
  }
  elsif ($x == $y) { # exactly the same reference
    1;
  }
  elsif ($refx eq 'SCALAR') {
    Compare($$x, $$y);
  }
  elsif ($refx eq 'ARRAY') {
    if ($#$x == $#$y) { # same length
      my $i = -1;
      for (@$x) {
	$i++;
	return 0 unless Compare($$x[$i], $$y[$i]);
      }
      1;
    }
    else {
      0;
    }
  }
  elsif ($refx eq 'HASH') {
    return 0 unless scalar keys %$x == scalar keys %$y;
    for (keys %$x) {
      next unless defined $$x{$_} || defined $$y{$_};
      return 0 unless defined $$y{$_} && Compare($$x{$_}, $$y{$_});
    }
    1;
  }
  elsif ($refx eq 'REF') {
    0;
  }
  elsif ($refx eq 'CODE') {
    0;
  }
  elsif ($refx eq 'GLOB') {
    0;
  }
  else { # a package name (object blessed)
    my ($type) = "$x" =~ m/^$refx=(\S+)\(/o;
    if ($type eq 'HASH') {
      my %x = %$x;
      my %y = %$y;
      Compare(\%x, \%y);
    }
    elsif ($type eq 'ARRAY') {
      my @x = @$x;
      my @y = @$y;
      Compare(\@x, \@y);
    }
    elsif ($type eq 'SCALAR') {
      my $x = $$x;
      my $y = $$y;
      Compare($x, $y);
    }
    elsif ($type eq 'GLOB') {
      0;
    }
    elsif ($type eq 'CODE') {
      0;
    }
    else {
      croak "Can't handle $type type.";
    }
  }
}

1;

=head1 NAME

Data::Compare - compare perl data structures

=head1 SYNOPSIS

    use Data::Compare;

    my $h = { 'foo' => [ 'bar', 'baz' ], 'FOO' => [ 'one', 'two' ] };
    my @a1 = ('one', 'two');
    my @a2 = ('bar', 'baz');
    my %v = ( 'FOO', \@a1, 'foo', \@a2 );

    # simple procedural interface
    print 'structures of $h and \%v are ',
      Compare($h, \%v) ? "" : "not ", "identical.\n";

    # OO usage
    my $c = new Data::Compare($h, \%v);
    print 'structures of $h and \%v are ',
      $c->Cmp ? "" : "not ", "identical.\n";
    # or
    my $c = new Data::Compare;
    print 'structures of $h and \%v are ',
      $c->Cmp($h, \%v) ? "" : "not ", "identical.\n";

=head1 DESCRIPTION

Compare two perl data structures recursively. Returns 0 if the
structures differ, else returns 1.

=head1 BUGS

C<Data::Compare> cheats with REF, CODE and GLOB references. If such a
reference is encountered in a structure being processed, the result is
0 unless references are equal.

Currently, there is no way to compare two compiled piece of code with
perl so there is no hope to add a better CODE references support in
C<Data::Compare> in a near future.

=head1 AUTHOR

Fabien Tassin        fta@sofaraway.org

Copyright (c) 1999-2001 Fabien Tassin. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 VERSION

Version 0.02    (25 Apr 2001)

=head1 SEE ALSO

perl(1), perlref(1)

=cut
