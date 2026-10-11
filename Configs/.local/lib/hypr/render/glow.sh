#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" glow style.json

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

if [[ -n "${render_job[pack_override]}" ]]; then
  render_write_pack_override render_job
else
  jq "${RENDER_PALETTE_ROLES_JQ}${RENDER_PALETTE_NUMBERED_JQ} | . as \$r | {
    document: {block_prefix: \"\\n\", block_suffix: \"\\n\", color: \$r.fg, margin: 2},
    block_quote: {indent: 1, indent_token: \"│ \", color: \$r.alt_fg},
    list: {level_indent: 2},
    heading: {block_suffix: \"\\n\", color: \$r.accent, bold: true},
    h1: {prefix: \" \", suffix: \" \", color: \$r.act_fg, background_color: \$r.act_bg, bold: true},
    h2: {prefix: \"## \"}, h3: {prefix: \"### \"}, h4: {prefix: \"#### \"},
    h5: {prefix: \"##### \"}, h6: {prefix: \"###### \", color: \$r.alt_fg, bold: false},
    emph: {italic: true}, strong: {bold: true}, strikethrough: {crossed_out: true},
    hr: {color: \$r.br, format: \"\\n--------\\n\"},
    item: {block_prefix: \"• \"}, enumeration: {block_prefix: \". \"},
    task: {ticked: \"[✓] \", unticked: \"[ ] \"},
    link: {color: \$r.info, underline: true}, link_text: {color: \$r.accent, bold: true},
    image: {color: \$r.info, underline: true},
    image_text: {color: \$r.alt_fg, format: \"Image: {{.text}} →\"},
    code: {prefix: \" \", suffix: \" \", color: \$r.act_fg, background_color: \$r.act_bg},
    code_block: {color: \$r.fg, margin: 2, chroma: (({
      text: \$r.fg, comment: \$r.alt_fg, comment_preproc: \$r.warning,
      keyword: \$r.accent, keyword_reserved: \$r.c5, keyword_namespace: \$r.c1,
      keyword_type: \$r.c4, operator: \$r.c1, punctuation: \$r.c3,
      name: \$r.fg, name_builtin: \$r.c4, name_tag: \$r.c5,
      name_attribute: \$r.c6, name_constant: \$r.c5, name_decorator: \$r.c3,
      name_function: \$r.success, literal_number: \$r.info,
      literal_string: \$r.warning, literal_string_escape: \$r.c6,
      generic_deleted: \$r.error, generic_inserted: \$r.success,
      generic_subheading: \$r.alt_fg
    } | with_entries(.value = {color: .value})) + {
      error: {color: \$r.act_fg, background_color: \$r.error},
      name_class: {color: \$r.fg, underline: true, bold: true},
      generic_emph: {italic: true}, generic_strong: {bold: true},
      background: {background_color: \$r.bg}
    })},
    definition_description: {block_prefix: \"\\n🠶 \"}
  }" "${render_job[palette_file]}" > "${render_job[staged_file]}"
fi

render_commit_staged_output render_job
trap - EXIT
