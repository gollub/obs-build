################################################################
#
# Author: Jan Blunck <jblunck@infradead.org>
#
# This file is part of build.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 or 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
#################################################################

package Build::LiveBuild;

use strict;

require File::Spec;

eval { require Archive::Tar; };
*Archive::Tar::new = sub {die("Archive::Tar is not available\n")} unless defined &Archive::Tar::new;

sub filter {
  my ($content) = @_;

  return '' unless defined $content;

  $content =~ s/^#.*$//mg;
  $content =~ s/^!.*$//mg;
  $content =~ s/^\s*//mg;
  return $content;
}

sub parse_package_list {
  my ($content, $flavour) = @_;
  my @packages = ();

  my @if_flavour = ();

  my @lines = split /\n/, ${$content};
  for (@lines) {
    my $line = $_;

    # Check for start of conditional
    if ($line =~ /^#if FLAVOUR (.*)$/) {
      die ("malformed package list: conditional in conditional") if @if_flavour;
      @if_flavour = split / /, $1;
    }

    # Check for end of conditional
    if ($line =~ /^#endif$/) {
      die ("malformed package list: unexpected #endif") unless @if_flavour;
      @if_flavour = ();
    }

    my $filtered = filter($line);

    # Just skip this line if we have a comment etc
    if ($filtered) {
      if (@if_flavour) {
        # If we're currently in a conditional, evaluate it before adding the
        # package to the list
        push @packages, $filtered if grep /^$flavour$/, @if_flavour;
      } else {
        push @packages, $filtered;
      }
    }
  }

  return @packages;
};

sub parse_archive {
  my ($content) = @_;
  my @repos;

  my @lines = split /\n/, filter($content);
  for (@lines) {
    next if /^deb-src /;

    die("bad path using not obs:/ URL: $_\n") unless $_ =~ /^deb\s+obs:\/\/\/?([^\s\/]+)\/([^\s\/]+)\/?\s+.*$/;
    push @repos, "$1/$2";
  }

  return @repos;
}

sub unify {
  my %h = map {$_ => 1} @_;
  return grep(delete($h{$_}), @_);
}

sub parse {
  my ($config, $filename, @args) = @_;
  my $ret = {};

  # check that filename is a tar
  my $tar = Archive::Tar->new;
  unless($tar->read($filename)) {
    warn("$filename: " . $tar->error . "\n");
    $ret->{'error'} = "$filename: " . $tar->error;
    return $ret;
  }

  # check that directory layout matches live-build directory structure
  for my $file ($tar->list_files('')) {
    next unless $file =~ /^(.*\/)?config\/archives\/.*\.list.*/;
    warn("$filename: config/archives/*.list* files not allowed!\n");
    $ret->{'error'} = "$filename: config/archives/*.list* files not allowed!";
    return $ret;
  }

  # get the flavour from the top level directory of the tar
  my $file = ($tar->list_files(''))[0];
  my $flavour = (File::Spec->splitdir($file))[0];

  # always require the list of packages required by live-boot for
  # bootstrapping the target distribution image (e.g. with debootstrap)
  my @packages = ( 'live-build-desc' );

  for my $file ($tar->list_files('')) {
    next unless $file =~ /^(.*\/)?config\/package-lists\/.*\.list.*/;
    push @packages, parse_package_list(\$tar->get_content($file), $flavour);
  }

  ($ret->{'name'} = $filename) =~ s/\.[^.]+$//;
  $ret->{'deps'} = [ unify(@packages) ];
  return $ret;
}

1;
