package Catalyst::Controller::SimpleCAS;
use strict;
use warnings;

# ABSTRACT: General-purpose content-addressed storage (CAS) for Catalyst

our $VERSION = 0.01;

use Moose;
use Types::Standard qw(:all);
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }
with 'Catalyst::Controller::SimpleCAS::Role::TextTranscode';

use Catalyst::Controller::SimpleCAS::Content;

use Module::Runtime;
use Try::Tiny;
use Catalyst::Utils;
use Path::Class qw(file dir);
use JSON::DWIW;
use MIME::Base64;
use String::Random;


has 'store_class', is => 'ro', default => sub{'Catalyst::Controller::SimpleCAS::Store::File'};
has 'store_path', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  my $c = $self->_app;
  # Default Cas Store path if none was supplied in the config:
  return dir( Catalyst::Utils::home($c), 'cas_store' )->stringify;
};

has 'Store' => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $class = $self->store_class;
    Module::Runtime::require_module($class);
    return $class->new(
      store_dir => $self->store_path
    );
  }
);

#has 'fetch_url_path', is => 'ro', isa => 'Str', default => '/simplecas/fetch_content/';

sub Content {
  my $self = shift;
  my $checksum = shift;
  my $filename = shift; #<-- optional
  return Catalyst::Controller::SimpleCAS::Content->new(
    Store     => $self->Store,
    checksum  => $checksum,
    filename  => $filename
  );
}

# Accepts a free-form string and tries to extract a Cas checksum and 
# filename from it. If it is successfully, and the checksum exists in 
# the Store, returns the Content object
sub uri_find_Content {
  my $self = shift;
  my $uri = shift or return undef;
  my @parts = split(/\//,$uri);
  
  while (scalar @parts > 0) {
    my $checksum = shift @parts;
    next unless ($checksum =~ /^[0-9a-f]{40}$/);
    my $filename = (scalar @parts == 1) ? $parts[0] : undef;
    my $Content = $self->Content($checksum,$filename) or next;
    return $Content;
  }
  return undef;
}

sub fetch_content: Local {
   my ($self, $c, $checksum, $filename) = @_;
  
  my $disposition = 'inline;filename="' . $checksum . '"';
  
  if ($filename) {
    $filename =~ s/\"/\'/g;
    $disposition = 'attachment; filename="' . $filename . '"';  
  }
  
  unless($self->Store->content_exists($checksum)) {
    $c->res->body('Does not exist');
    return;
  }
  
  my $type = $self->Store->content_mimetype($checksum) or die "Error reading mime type";
  
  # type overrides for places where File::MimeInfo::Magic is known to guess wrong
  if($type eq 'application/vnd.ms-powerpoint' || $type eq 'application/zip') {
    my $Content = $self->Content($checksum,$filename);
    my $ext = lc($Content->file_ext);
    $type = 
      $ext eq 'doc'  ? 'application/msword' :
      $ext eq 'xls'  ? 'application/vnd.ms-excel' :
      $ext eq 'docx' ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
      $ext eq 'xlsx' ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' :
      $ext eq 'pptx' ? 'application/vnd.openxmlformats-officedocument.presentationml.presentation' :
    $type;
  }
  
  $c->response->header('Content-Type' => $type);
  $c->response->header('Content-Disposition' => $disposition);
  return $c->res->body( $self->Store->fetch_content_fh($checksum) );
}


sub upload_content: Local  {
  my ($self, $c) = @_;

  my $upload = $c->req->upload('Filedata') or die "no upload object";
  my $checksum = $self->Store->add_content_file_mv($upload->tempname) or die "Failed to add content";
  
  return $c->res->body($checksum);
}


sub upload_image: Local  {
  my ($self, $c, $maxwidth, $maxheight) = @_;

  my $upload = $c->req->upload('Filedata') or die "no upload object";
  
  my ($type,$subtype) = split(/\//,$upload->type);
  
  my $resized = \0;
  my $shrunk = \0;
  
  my ($checksum,$width,$height,$orig_width,$orig_height);
  
  try {
    # Will die unless Image::Resize is available, which is now optional (Github Issue #42)
    ($checksum,$width,$height,$resized,$orig_width,$orig_height) 
      = $self->add_resize_image($upload->tempname,$type,$subtype,$maxwidth,$maxheight);
  }
  catch {
    # Fall-back calculates new image size without actually resizing it. The img
    # tag will still be smaller, but the image file will be original dimensions
    ($checksum,$width,$height,$shrunk,$orig_width,$orig_height) 
      = $self->add_size_info_image($upload->tempname,$type,$subtype,$maxwidth,$maxheight);
  };
  
  
  unlink $upload->tempname;
  
  #my $tag = '<img src="/simplecas/fetch_content/' . $checksum . '"';
  #$tag .= ' width=' . $width . ' height=' . $height if ($width and $height);
  #$tag .= '>';
  
  # TODO: fix this API!!!
  
  my $packet = {
    success => \1,
    checksum => $checksum,
    height => $height,
    width => $width,
    resized => $resized,
    shrunk => $shrunk,
    orig_width => $orig_width,
    orig_height => $orig_height,
    filename => $self->safe_filename($upload->filename),
  };
  
  return $c->res->body(JSON::DWIW->to_json($packet));
}



sub add_resize_image :Private {
  my ($self,$file,$type,$subtype,$maxwidth,$maxheight) = @_;
  
  Module::Runtime::require_module('Image::Resize');

  my $checksum = $self->Store->add_content_file($file) or die "Failed to add content";
  
  my $resized = \0;
  
  my ($width,$height) = $self->Store->image_size($checksum);
  my ($orig_width,$orig_height) = ($width,$height);
  if (defined $maxwidth) {
    
    my ($newwidth,$newheight) = ($width,$height);
    
    if($width > $maxwidth) {
      my $ratio = $maxwidth/$width;
      $newheight = int($ratio * $height);
      $newwidth = $maxwidth;
    }
    
    if(defined $maxheight and $newheight > $maxheight) {
      my $ratio = $maxheight/$newheight;
      $newwidth = int($ratio * $newwidth);
      $newheight = $maxheight;
    }
    
    unless ($newwidth == $width && $newheight == $height) {
    
      my $image = Image::Resize->new($self->Store->checksum_to_path($checksum));
      my $gd = $image->resize($newwidth,$newheight);
      
      my $method = 'png';
      $method = $subtype if ($gd->can($subtype));
      
      my $tmpfile = file(
        Catalyst::Utils::class2tempdir($self->_app,1),
        String::Random->new->randregex('[a-z0-9A-Z]{15}')
      );
      
      $tmpfile->spew( $gd->$method );
      
      my $newchecksum = $self->Store->add_content_file_mv($tmpfile->stringify);
      
      ($checksum,$width,$height) = ($newchecksum,$newwidth,$newheight);
      $resized = \1;
    }
  }
  
  return ($checksum,$width,$height,$resized,$orig_width,$orig_height);
}


# New method, uses the same API as 'add_resize_image' above, but doesn't
# do any actual resizing (just calculates smaller height/width for better
# display). This method is used when Image::Resize is not available.
# Added for RapidApp Github Issue #42
sub add_size_info_image :Private {
  my ($self,$file,$type,$subtype,$maxwidth,$maxheight) = @_;

  my $checksum = $self->Store->add_content_file($file) or die "Failed to add content";

  my $shrunk = \0;

  my ($width,$height) = $self->Store->image_size($checksum);
  my ($orig_width,$orig_height) = ($width,$height);
  if (defined $maxwidth) {
    
    my ($newwidth,$newheight) = ($width,$height);
    
    if($width > $maxwidth) {
      my $ratio = $maxwidth/$width;
      $newheight = int($ratio * $height);
      $newwidth = $maxwidth;
    }
    
    if(defined $maxheight and $newheight > $maxheight) {
      my $ratio = $maxheight/$newheight;
      $newwidth = int($ratio * $newwidth);
      $newheight = $maxheight;
    }
    
    unless ($newwidth == $width && $newheight == $height) {
      ($width,$height) = ($newwidth,$newheight);
      $shrunk = \1;
    }
  }

  return ($checksum,$width,$height,$shrunk,$orig_width,$orig_height);
}


sub upload_file : Local {
  my ($self, $c) = @_;
  
  my $upload = $c->req->upload('Filedata') or die "no upload object";
  my $checksum = $self->Store->add_content_file_mv($upload->tempname) or die "Failed to add content";
  my $Content = $self->Content($checksum,$upload->filename);
  
  my $packet = {
    success  => \1,
    filename => $self->safe_filename($upload->filename),
    checksum  => $Content->checksum,
    mimetype  => $Content->mimetype,
    css_class => $Content->filelink_css_class,
  };
  
  return $c->res->body(JSON::DWIW->to_json($packet));
}


sub safe_filename {
  my $self = shift;
  my $filename = shift;
  
  my @parts = split(/[\\\/]/,$filename);
  return pop @parts;
}


sub upload_echo_base64: Local  {
  my ($self, $c) = @_;

  my $upload = $c->req->upload('Filedata') or die "no upload object";
  
  my $base64 = encode_base64($upload->slurp,'');
  
  my $packet = {
    success => \1,
    echo_content => $base64
  };
  
  return $c->res->body(JSON::DWIW->to_json($packet));
}


1;


__END__

=head1 NAME

Catalyst::Controller::SimpleCAS - General-purpose content-addressed storage (CAS) module

=head1 SYNOPSIS

 use Catalyst::Controller::SimpleCAS;
 ...

=head1 DESCRIPTION

This controller provides a simple content-addressed storage backend for Catalyst applications. 

This module was originally developed within L<RapidApp> before being extracted into its own module.


=head1 ATTRIBUTES

=head2 store_class

Object class to use for the Store backend. Defaults to 
C<Catalyst::Controller::SimpleCAS::Store::File>

=head2 store_path

Directory/path to be used by the Store. Defaults to C<cas_store> within the Catalyst home directory.

=head2 Store

Actual object instance of the Store. By default this object is built using the C<store_class> (by 
calling C<new()>) with the C<store_path> supplied to the constructor.

=head1 PUBLIC ACTIONS

=head2 upload_content

Upload new content to the CAS and return the sha1 checksum in the body to be able to access it later. 
Because of the CAS design, the system automatically deduplicates, and will only ever store
a single copy of a given unique piece of content in the Store. 

=head2 fetch_content

Fetch existing content from the CAS according its sha1 checksum. 

Example:

  GET /simplecas/fetch_content/fdb379f7e9c8d0a1fcd3b5ee4233d88c5a4a023e

The system attempts to identify the content type and sets the MIME type accordingly. Additionally,
an optional filename argument can be also be supplied in the URL

  GET /simplecas/fetch_content/fdb379f7e9c8d0a1fcd3b5ee4233d88c5a4a023e/somefile.txt

The main reason this is supported is simply for more human-friendly URLs. The name is not stored
or validated in any way. If supplied, this does nothing other than being used to set the 
content-disposition:

  Content-Disposition: attachment; filename="somefile.txt"

When there is no filename second arg supplied, the content-disposition is set like this:

  Content-Disposition: inline;filename="fdb379f7e9c8d0a1fcd3b5ee4233d88c5a4a023e"


=head2 upload_file

Works like C<upload_content>, but returns a JSON packet with additional metadata/information in
the body.

=head2 upload_image

Works like C<upload_file>, but with some image-specific functionality, including client-supplied
max width and height values supplied as the first and second args, respectively. For example,
a POST I<upload> with I<Filedata> containing an image, and declared max size of 800x600 uses a
URL like:

  POST /simplecas/upload_image/800/600

When the image is larger than the max width or height, I<if> the optional dependency 
L<Image::Resize> is available (which requires L<GD>) it is used to resize the image, preserving
height/width proportions accordingly, and the new, resized image is what is stored in the CAS.
Otherwise, the image is not resized, but resized dimensions are returned in the JSON packet
so the client can generate an C<img> tag for display.

Originally, L<Image::Resize> was a standard dependency, but this can be a PITA to get installed
with all of the dependencies of L<GD>.

=head2 upload_echo_base64

This does nothing but accept a standard POST/Filedata upload and return it as base64 in a JSON
packet within the JSON/object key C<echo_content>.

=head1 METHODS

=head2 Content

Not usually called directly

=head2 add_resize_image

Not usually called directly

=head2 add_size_info_image

Not usually called directly

=head2 safe_filename

Not usually called directly

=head2 uri_find_Content

Not usually called directly

=head1 SEE ALSO

=over

=item *

L<Catalyst>

=item *

L<Catalyst::Controller>

=item * 

L<RapidApp>

=back

=head1 AUTHOR

Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by IntelliTree Solutions llc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
