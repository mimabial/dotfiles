# Input: "section<TAB>key<TAB>value" records, then the INI file to merge them into.
BEGIN { FS = "\t" }

function queue(section, key, value) {
  if (!((section, key) in pending)) keys[section, ++key_count[section]] = key
  if (!(section in queued)) section_order[++section_total] = section
  queued[section] = 1
  pending[section, key] = value
}
function emit(section, key) {
  if ((section, key) in written) return
  print key "=" pending[section, key]
  written[section, key] = 1
}
function flush_section(section,   i) {
  for (i = 1; i <= key_count[section]; i++) emit(section, keys[section, i])
}

FILENAME == ARGV[1] {
  if (NF < 3 || $1 == "" || $2 == "") next
  value = $3
  for (field = 4; field <= NF; field++) value = value FS $field
  queue($1, $2, value)
  next
}
/^[[:space:]]*\[/ {
  if (current != "") flush_section(current)
  name = $0
  sub(/^[[:space:]]*\[/, "", name)
  sub(/\][[:space:]]*$/, "", name)
  current = (name in queued) ? name : ""
  if (current != "") found[current] = 1
  lines++
  print
  next
}
current != "" {
  key = $0
  sub(/=.*$/, "", key)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
  if ((current, key) in pending) {
    emit(current, key)
    lines++
    next
  }
}
{
  lines++
  print
}
END {
  if (current != "") flush_section(current)
  for (i = 1; i <= section_total; i++) {
    if (section_order[i] in found) continue
    if (lines > 0) print ""
    print "[" section_order[i] "]"
    flush_section(section_order[i])
    lines++
  }
}
