#${PMpre} EDG::WP4::CCM::Element${PMpost}

use EDG::WP4::CCM::Path qw(escape unescape);

use EDG::WP4::CCM::CacheManager::Encode qw(
    PROPERTY RESOURCE
    STRING LONG DOUBLE BOOLEAN
    LIST NLIST);

use parent qw(Exporter);

warn "Direct usage of EDG::WP4::CCM::Element is deprecated ",
    "and contains no functional code besides a limited number ",
    "of reexported functions and constants from other modules.";

our @EXPORT    = qw(unescape);
our @EXPORT_OK = qw(
    PROPERTY RESOURCE
    STRING LONG DOUBLE BOOLEAN
    LIST NLIST
    escape);

1;
