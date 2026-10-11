dev_env_install_scala() {
  dev_env_install_with_mise "Scala" java@latest scala@latest sbt@latest
  hyprshell pm add scala-cli
}
