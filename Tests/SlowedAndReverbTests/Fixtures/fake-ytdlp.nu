#!/usr/bin/env nu

def --wrapped main [...args: string] {
  let url = ($args | last)
  if $url == "--version" {
    print "fake-ytdlp"
  } else if $url == "https://example.test/playlist" {
    print '{"id":"playlist","title":"Playlist","entries":[{"id":"aaaaaaaaaaa","title":"One"},{"id":"bbbbbbbbbbb","title":"Two"}]}'
  } else if $url == "https://www.youtube.com/watch?v=aaaaaaaaaaa" {
    sleep 100ms
    print '{"id":"aaaaaaaaaaa","title":"Artist A - One","artist":"Artist A","webpage_url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","duration":123}'
  } else if $url == "https://www.youtube.com/watch?v=bbbbbbbbbbb" {
    print '{"id":"bbbbbbbbbbb","title":"Two","channel":"Artist B - Topic","webpage_url":"https://www.youtube.com/watch?v=bbbbbbbbbbb","duration":234}'
  } else {
    print --stderr $"unexpected arguments: ($args)"
    exit 1
  }
}
