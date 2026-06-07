# Compatibility shim.
#
# Jekyll::Excerpt uses Forwardable to delegate `yaml_file?` to its document.
# On recent Ruby patch releases (3.2.11 / 3.3.11+), Forwardable raises
# NoMethodError when the delegated target is a *private* method, and
# Jekyll::Convertible#yaml_file? is private. Excerpt generation for a page
# therefore crashes the whole build. Making the method public fixes the
# delegation without changing behaviour.
#
# (Runs because our GitHub Actions build uses `bundle exec jekyll build`, which
# loads _plugins/ — unlike GitHub's restricted built-in Pages build.)
require "jekyll"

module Jekyll
  module Convertible
    public :yaml_file? if private_method_defined?(:yaml_file?)
  end
end
