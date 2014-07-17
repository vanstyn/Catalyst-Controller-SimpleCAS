# -*- perl -*-

use strict;
use warnings;
use FindBin '$Bin';
use lib "$Bin/lib";

use Test::More;
use Test::Exception;

use_ok('Catalyst::Controller::SimpleCAS');
use_ok('Catalyst::Plugin::SimpleCAS');


done_testing;
