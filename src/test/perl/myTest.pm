#
# Test.pm
#
# $Id: myTest.pm,v 1.1 2006/06/26 14:20:41 gcancio Exp $
#
# Copyright (c) 2001 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#

package   myTest;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use Test::More;# qw (ok);

BEGIN{
 use      Exporter;
 use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

 @ISA       = qw(Exporter);
 @EXPORT    = qw();           
 @EXPORT_OK = qw(eok make_file);
 $VERSION   = 1.00;        
}


my $ec = LC::Exception::Context->new->will_store_errors;

sub eok ($$$) {
  my ($cec, $result, $descr) = @_;
  unless ($result) {
    if ($cec->error) {
      ok (1, "exception: $descr");
      $cec->ignore_error();
      return SUCCESS;
    }
  } 
  ok (0, "exception: $descr");
}

sub make_file {
    my ($fn, $data) = @_;
    open(my $fh, ">", $fn);
    print $fh $data if (defined($data));
    close($fh);
}

1;
