# -*- perl -*-

use strict;
use warnings;
use FindBin '$Bin';
use File::Spec::Functions 'catfile', 'catdir', 'tmpdir';
use File::Path 'make_path', 'remove_tree';
use lib "$Bin/lib";

use Test::More;
use Test::Exception;

use_ok('Catalyst::Controller::SimpleCAS::Store::File');

# Create a CAS structure within the test directory here.

my $cas_dir= catdir( $Bin, 'tmp', 'cas' );

-d $cas_dir or mkdir $cas_dir or die "Can't create tmpdir $cas_dir";
remove_tree($cas_dir) if -d $cas_dir;
make_path($cas_dir);

my $file_cas= new_ok 'Catalyst::Controller::SimpleCAS::Store::File',
	[ store_dir => $cas_dir ], "create CAS instance on $cas_dir";

# Write a dummy file to the system temp path to simulate what Catalyst would
# use for a file upload.
my $origin_file= catfile(tmpdir(), 'incoming.txt');
{
	open my $fh, '>:raw', $origin_file or die "open: $!";
	print $fh "This file simulates a Catalyst upload to the temp directory\n";
	close $fh;
}

my $cksum= $file_cas->add_content_file_mv($origin_file);
is( $cksum, '437c659b4c0fea1304edea50c2cdd420f8c0f6f6', 'file hashed correctly' );

ok( -e $file_cas->checksum_to_path($cksum), 'new file exists' );
ok( !-e $origin_file, 'old file removed' );

done_testing;
