# Clojure installer.

dev_env_install_clojure() {
  printf 'Installing Clojure...\n\n'
  hyprshell pm add rlwrap
  dev_env_install_with_mise "Clojure" clojure@latest
}
