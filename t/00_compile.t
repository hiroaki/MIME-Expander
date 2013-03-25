use strict;
use Test::More tests => 7;

BEGIN { use_ok 'MIME::Expander' }
BEGIN { use_ok 'MIME::Expander::Plugin' }
BEGIN { use_ok 'MIME::Expander::Plugin::ApplicationTar' }
BEGIN { use_ok 'MIME::Expander::Plugin::ApplicationXBzip2' }
BEGIN { use_ok 'MIME::Expander::Plugin::ApplicationXGzip' }
BEGIN { use_ok 'MIME::Expander::Plugin::ApplicationZip' }
BEGIN { use_ok 'MIME::Expander::Plugin::MessageRFC822' }
