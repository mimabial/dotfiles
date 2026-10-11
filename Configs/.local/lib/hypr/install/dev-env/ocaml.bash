dev_env_install_ocaml() {
  local installer=""

  printf 'Installing OCaml...\n\n'
  installer="$(curl -fsSL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh)" || return 1
  bash -c "${installer}"
  opam init --yes
  eval "$(opam env)"
  opam install ocaml-lsp-server odoc ocamlformat utop --yes
}
