# Ruby and Rails installer.

dev_env_configure_ruby_tooling() {
  mise settings add idiomatic_version_file_enable_tools ruby
  mise settings add ruby.compile false
}

dev_env_configure_gem_defaults() {
  printf 'gem: --no-document\n' >"$HOME/.gemrc"
}

dev_env_install_ruby() {
  printf 'Installing Ruby on Rails...\n\n'
  hyprshell pkg/add.sh libyaml
  dev_env_install_with_mise "Ruby" ruby@latest
  dev_env_configure_ruby_tooling
  dev_env_configure_gem_defaults
  mise x ruby -- gem install rails --no-document
  printf '\nYou can now run: rails new myproject\n'
}
