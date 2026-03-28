#!/bin/bash

usage() {
  echo "Usage: hyprshell install/dev-env.sh <ruby|node|bun|go|laravel|symfony|php|python|elixir|phoenix|rust|java|zig|ocaml|dotnet|clojure|scala>" >&2
  exit 1
}

require_runtime() {
  [[ -n "${1:-}" ]] || usage
}

install_mise_tools() {
  local tool=""
  for tool in "$@"; do
    mise use --global "${tool}"
  done
}

install_php() {
  local php_ini_path="/etc/php/php.ini"
  local extensions_to_enable=(
    bcmath
    intl
    iconv
    openssl
    pdo_sqlite
    pdo_mysql
  )
  local ext=""

  sudo pacman -S php composer php-sqlite xdebug --noconfirm

  if [[ ":$PATH:" != *":$HOME/.config/composer/vendor/bin:"* ]]; then
    echo 'export PATH="$HOME/.config/composer/vendor/bin:$PATH"' >>"$HOME/.bashrc"
    source "$HOME/.bashrc"
    echo "Added Composer global bin directory to PATH."
  else
    echo "Composer global bin directory already in PATH."
  fi

  sudo sed -i \
    -e 's/^;zend_extension=xdebug.so/zend_extension=xdebug.so/' \
    -e 's/^;xdebug.mode=debug/xdebug.mode=debug/' \
    /etc/php/conf.d/xdebug.ini

  for ext in "${extensions_to_enable[@]}"; do
    sudo sed -i "s/^;extension=${ext}/extension=${ext}/" "$php_ini_path"
  done
}

install_node() {
  echo -e "Installing Node.js...\n"
  install_mise_tools node@lts
}

install_python() {
  echo -e "Installing Python...\n"
  install_mise_tools python@latest
  echo -e "\nInstalling uv...\n"
  curl -fsSL https://astral.sh/uv/install.sh | sh
}

install_elixir_stack() {
  install_mise_tools erlang@latest elixir@latest
  mise x elixir -- mix local.hex --force
}

install_ruby() {
  echo -e "Installing Ruby on Rails...\n"
  hyprshell pkg/add.sh libyaml
  install_mise_tools ruby@latest
  mise settings add idiomatic_version_file_enable_tools ruby
  mise settings add ruby.compile false
  echo "gem: --no-document" >"$HOME/.gemrc"
  mise x ruby -- gem install rails --no-document
  echo -e "\nYou can now run: rails new myproject"
}

install_bun() {
  echo -e "Installing Bun...\n"
  install_mise_tools bun@latest
}

install_deno() {
  echo -e "Installing Deno...\n"
  install_mise_tools deno@latest
}

install_go() {
  echo -e "Installing Go...\n"
  install_mise_tools go@latest
}

install_laravel() {
  echo -e "Installing PHP and Laravel...\n"
  install_php
  install_node
  composer global require laravel/installer
  echo -e "\nYou can now run: laravel new myproject"
}

install_symfony() {
  echo -e "Installing PHP and Symfony...\n"
  install_php
  hyprshell pkg/add.sh symfony-cli
  echo -e "\nYou can now run: symfony new --webapp myproject"
}

install_elixir() {
  echo -e "Installing Elixir...\n"
  install_elixir_stack
}

install_phoenix() {
  echo -e "Installing Phoenix Framework...\n"
  install_elixir_stack
  mise x elixir -- mix local.rebar --force
  mise x elixir -- mix archive.install hex phx_new --force
  echo -e "\nYou can now run: mix phx.new my_app"
}

install_rust() {
  echo -e "Installing Rust...\n"
  bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)" -- -y
}

install_java() {
  echo -e "Installing Java...\n"
  install_mise_tools java@latest
}

install_zig() {
  echo -e "Installing Zig...\n"
  install_mise_tools zig@latest zls@latest
}

install_ocaml() {
  echo -e "Installing OCaml...\n"
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh)"
  opam init --yes
  eval "$(opam env)"
  opam install ocaml-lsp-server odoc ocamlformat utop --yes
}

install_dotnet() {
  echo -e "Installing .NET...\n"
  install_mise_tools dotnet@latest
}

install_clojure() {
  echo -e "Installing Clojure...\n"
  hyprshell pkg/add.sh rlwrap
  install_mise_tools clojure@latest
}

install_scala() {
  echo -e "Installing Scala...\n"
  install_mise_tools java@latest scala@latest sbt@latest
  hyprshell pkg/add.sh scala-cli
}

require_runtime "${1:-}"

case "$1" in
  ruby) install_ruby ;;
  node) install_node ;;
  bun) install_bun ;;
  deno) install_deno ;;
  go) install_go ;;
  php) echo -e "Installing PHP...\n"; install_php ;;
  laravel) install_laravel ;;
  symfony) install_symfony ;;
  python) install_python ;;
  elixir) install_elixir ;;
  phoenix) install_phoenix ;;
  rust) install_rust ;;
  java) install_java ;;
  zig) install_zig ;;
  ocaml) install_ocaml ;;
  dotnet) install_dotnet ;;
  clojure) install_clojure ;;
  scala) install_scala ;;
  *) usage ;;
esac
