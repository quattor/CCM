#
# myTest.pm
#

package   myTest;

use strict;
use warnings;

use LC::Exception qw(SUCCESS throw_error);
use Test::More;
use File::Path qw(make_path);

BEGIN{
 use      Exporter;
 use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

 @ISA       = qw(Exporter);
 @EXPORT    = qw();           
 @EXPORT_OK = qw(eok make_file compile_profile);
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

sub compile_profile
{
    my ($type, $name) = @_;
    make_path("target/test/$type");
    system("cd src/test/resources && panc --formats $type --output-dir ../../../target/test/$type $name.pan");
}

1;
