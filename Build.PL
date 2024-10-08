
# This file was automatically generated by Dist::Zilla::Plugin::ModuleBuild v6.031.
use strict;
use warnings;

use Module::Build 0.28;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.28"
  },
  "configure_requires" => {
    "Module::Build" => "0.28"
  },
  "dist_abstract" => "drop in replacement for Dancer::Plugin::Catmandu::SRU",
  "dist_author" => [
    "=over 4"
  ],
  "dist_name" => "Plack-App-Catmandu-SRU",
  "dist_version" => "0.02",
  "license" => "perl",
  "module_name" => "Plack::App::Catmandu::SRU",
  "recursive_test_files" => 1,
  "requires" => {
    "Catmandu" => "1.20",
    "Catmandu::Exporter::Template" => "0.11",
    "Plack" => 0,
    "SRU" => "1.01",
    "Type::Tiny" => 0,
    "namespace::clean" => 0,
    "perl" => "v5.20.0"
  },
  "test_requires" => {
    "Test::More" => "0.88"
  }
);


my %fallback_build_requires = (
  "Module::Build" => "0.28",
  "Test::More" => "0.88"
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

my $build = Module::Build->new(%module_build_args);


$build->create_build_script;
