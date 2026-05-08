# PHP-family installers.

dev_env_php_enable_xdebug() {
  sudo sed -i \
    -e 's/^;zend_extension=xdebug.so/zend_extension=xdebug.so/' \
    -e 's/^;xdebug.mode=debug/xdebug.mode=debug/' \
    /etc/php/conf.d/xdebug.ini
}

dev_env_php_enable_extensions() {
  local php_ini_path="/etc/php/php.ini"
  local ext=""
  local -a extensions=(
    bcmath
    intl
    iconv
    openssl
    pdo_sqlite
    pdo_mysql
  )

  for ext in "${extensions[@]}"; do
    sudo sed -i "s/^;extension=${ext}/extension=${ext}/" "${php_ini_path}"
  done
}

dev_env_php_configure_composer_path() {
  local export_line='export PATH="$HOME/.config/composer/vendor/bin:$PATH"'
  dev_env_ensure_bashrc_path "${export_line}"
}

dev_env_install_php_runtime() {
  printf 'Installing PHP...\n\n'
  hyprshell pm add php composer php-sqlite xdebug
  dev_env_php_configure_composer_path
  dev_env_php_enable_xdebug
  dev_env_php_enable_extensions
}

dev_env_install_laravel() {
  printf 'Installing PHP and Laravel...\n\n'
  dev_env_install_php_runtime
  dev_env_install_simple_runtime "Node.js" node@lts
  composer global require laravel/installer
  printf '\nYou can now run: laravel new myproject\n'
}

dev_env_install_symfony() {
  printf 'Installing PHP and Symfony...\n\n'
  dev_env_install_php_runtime
  hyprshell pm add symfony-cli
  printf '\nYou can now run: symfony new --webapp myproject\n'
}
