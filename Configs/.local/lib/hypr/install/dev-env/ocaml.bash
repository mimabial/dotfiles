# OCaml installer.

dev_env_install_ocaml() {
  printf 'Installing OCaml...\n\n'
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh)"
  opam init --yes
  eval "$(opam env)"
  opam install ocaml-lsp-server odoc ocamlformat utop --yes
}
