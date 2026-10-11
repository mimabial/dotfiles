dev_env_install_clojure() {
  dev_env_install_with_mise "Clojure" clojure@latest
  hyprshell pm add rlwrap
}
