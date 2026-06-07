# Compatibility shim.
#
# Jekyll::Excerpt uses Forwardable to delegate `yaml_file?` to its document.
# On recent Ruby patch releases (3.2.11 / 3.3.11+), Forwardable raises
# NoMethodError when the delegated target is a *private* method, and
# Jekyll's `yaml_file?` is private — so excerpt generation crashes the build.
# Force it public on the relevant classes (works even for inherited methods).
#
# (Runs because our GitHub Actions build uses `bundle exec jekyll build`, which
# loads _plugins/ — unlike GitHub's restricted built-in Pages build.)
require "jekyll"

[Jekyll::Convertible, Jekyll::Page, Jekyll::Document, Jekyll::Excerpt].each do |mod|
  begin
    mod.send(:public, :yaml_file?)
  rescue NameError
    # method not present on this class; ignore
  end
end
Jekyll.logger.info "excerpt-shim:", "yaml_file? made public"
