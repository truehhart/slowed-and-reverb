#!/usr/bin/env nu

# Enforces one non-private top-level type per Swift source file, named after
# the file. Scans Sources/**/*.swift for actor/class/struct/enum/protocol
# declared at column 0 (optionally preceded by attribute lines and modifiers
# like public/final/nonisolated/@MainActor/@Observable/@main). Nested types
# (indented), extensions, and private/fileprivate declarations are ignored.
# Fails with exit 1 listing each offender as `file: typename`.

const pattern = '^(?:(?:public|internal|package|open|final|nonisolated(?:\(unsafe\))?|static|indirect|dynamic|convenience|@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?)\s+)*(?<keyword>actor|class|struct|enum|protocol)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)'

def main [] {
  let files = (glob Sources/**/*.swift)
  mut violations = []

  for file in $files {
    let base = ($file | path basename | str replace --regex '\.swift$' '')
    let names = (
      open --raw $file | decode utf-8 | lines
      | reduce --fold [] {|line, acc|
          let matched = ($line | parse --regex $pattern)
          if ($matched | is-empty) { $acc } else { $acc | append ($matched | get name) }
        }
    )

    if ($names | length) > 1 {
      for n in $names {
        $violations = ($violations | append $"($file): ($n)")
      }
    } else if (($names | length) == 1) and (($names | first) != $base) {
      $violations = ($violations | append $"($file): ($names | first)")
    }
  }

  if ($violations | is-empty) {
    print "check:structure ok — one non-private top-level type per file"
  } else {
    print "file-structure violations (each file must declare exactly one non-private top-level type named after the file):"
    for v in $violations { print $"  ($v)" }
    exit 1
  }
}
