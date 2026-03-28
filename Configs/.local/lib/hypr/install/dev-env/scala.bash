# Scala installer.

dev_env_install_scala() {
  printf 'Installing Scala...\n\n'
  dev_env_install_with_mise "Scala" java@latest scala@latest sbt@latest
  hyprshell pkg/add.sh scala-cli
}
