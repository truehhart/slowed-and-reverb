#!/usr/bin/env nu
# Guard the el()-throws-on-missing-id trap: every id main.ts requires via el()
# must exist in index.html. Fast, zero-dep pre-commit gate.

def main [] {
  let html = (open --raw index.html | decode utf-8)
  let ts = (open --raw src/main.ts | decode utf-8)

  let ids = (
    $ts
    | parse --regex 'el<[^>]*>\("(?<id>[^"]+)"\)'
    | get id
    | uniq
  )

  let missing = ($ids | where {|id| not ($html | str contains $'id="($id)"') })

  if ($missing | is-empty) {
    print $"check:dom ok — ($ids | length) required ids present in index.html"
  } else {
    print $"check:dom FAILED — missing in index.html: ($missing | str join ', ')"
    exit 1
  }
}
