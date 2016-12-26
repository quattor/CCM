BEGIN {
    our $TQU = <<'EOF';
[load]
prefix=EDG::WP4::CCM::
modules=CacheManager,CCfg,CLI,CacheManager::Configuration,CacheManager::DB,CacheManager::Element,Fetch,Fetch::JSONProfileSimple,Fetch::JSONProfileTyped,Options,Path,CacheManager::Resource,TextRender,TextRender::Scalar,Fetch::XMLPanProfile
[tt]
component=CCM
skippan=1
[doc]
poddirs=target/lib/perl,target/sbin
panpaths=NOPAN
EOF

    use EDG::WP4::CCM::Path qw(set_safe_unescape);
    set_safe_unescape('/special/safe_unescape');
    $EDG::WP4::CCM::Path::_safe_unescape_restore = ['/special/safe_unescape'];
}
use Test::Quattor::Unittest;
