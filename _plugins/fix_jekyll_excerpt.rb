# Compatibility shim.
#
# Jekyll::Excerpt uses Forwardable to delegate `yaml_file?` to its document.
# On recent Ruby patch releases (3.2.11 / 3.3.11+), Forwardable raises
# NoMethodError when the delegated target is a *private* method. Whichever of
# Convertible / Page / Document actually defines `yaml_file?` privately, make it
# public so the delegation works and excerpt generation stops crashing the build.
#
# (Runs because our GitHub Actions build uses `bundle exec jekyll build`, which
# loads _plugins/ — unlike GitHub's restricted built-in Pages build.)
require "jekyll"

[Jekyll::Convertible, Jekyll::Page, Jekyll::Document].each do |mod|
  if mod.private_instance_methods(false).include?(:yaml_file?)
    mod.send(:public, :yaml_file?)
    Jekyll.logger.info "excerpt-shim:", "made #{mod}#yaml_file? public"
  end
end
