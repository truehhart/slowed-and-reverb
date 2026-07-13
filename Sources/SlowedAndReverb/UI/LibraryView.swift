import SwiftUI

struct LibraryView: View {
  @Environment(PlayerModel.self) private var player
  @State private var model = LibraryModel()
  @State private var songToRemove: LibrarySong?
  @State private var playlistToRemove: LibraryPlaylist?

  let statusLine: StatusLine

  var body: some View {
    ModuleBox("library") {
      VStack(spacing: 10) {
        if let playlist = model.selectedPlaylist {
          playlistHeader(playlist)
        } else {
          sectionHeader
        }
        controls
        content
      }
    }
    .task { await model.load(using: player) }
    .confirmationDialog(
      "Remove \(songToRemove?.track.title ?? "song")?",
      isPresented: Binding(
        get: { songToRemove != nil }, set: { if !$0 { songToRemove = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove Song", role: .destructive) {
        guard let song = songToRemove else { return }
        Task {
          let removed = await model.removeSong(id: song.id, using: player)
          statusLine.show(removed ? "Removed \(song.track.title)" : "Could not remove song")
          songToRemove = nil
        }
      }
    } message: {
      Text("Downloaded audio and artwork will be permanently deleted.")
    }
    .confirmationDialog(
      "Remove \(playlistToRemove?.title ?? "playlist")?",
      isPresented: Binding(
        get: { playlistToRemove != nil }, set: { if !$0 { playlistToRemove = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove Playlist", role: .destructive) {
        guard let playlist = playlistToRemove else { return }
        Task {
          let removed = await model.removePlaylist(id: playlist.id, using: player)
          statusLine.show(removed ? "Removed \(playlist.title)" : "Could not remove playlist")
          playlistToRemove = nil
        }
      }
    } message: {
      Text("Songs and downloaded files will remain in your library.")
    }
  }

  private var sectionHeader: some View {
    HStack {
      Picker("Library section", selection: $model.section) {
        ForEach(LibraryModel.Section.allCases, id: \.self) { section in
          Text(section.rawValue.capitalized).tag(section)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 220)
      Spacer()
      Text(resultCount)
        .font(Theme.mono(10))
        .foregroundStyle(Theme.dim)
    }
  }

  private func playlistHeader(_ playlist: LibraryPlaylist) -> some View {
    HStack(spacing: 10) {
      Button {
        model.selectedPlaylistID = nil
        model.query = ""
      } label: {
        Label("Back", systemImage: "chevron.left")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Back to playlists")
      Text(playlist.title)
        .font(Theme.archivo(15, .bold))
        .lineLimit(1)
      Spacer()
      Button("Play All") {
        Task {
          await player.playLibraryTracks(playlist.tracks)
          statusLine.show("Playing \(playlist.title)")
        }
      }
      Button("Add All") {
        player.addLibraryTracks(playlist.tracks)
        statusLine.show("Added \(playlist.tracks.count) songs to queue")
      }
      Button("Remove", role: .destructive) { playlistToRemove = playlist }
        .accessibilityLabel("Remove playlist \(playlist.title)")
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      TextField(
        model.selectedPlaylist == nil ? "Search library" : "Search playlist", text: $model.query
      )
      .textFieldStyle(.roundedBorder)
      .accessibilityLabel("Search library")
      if model.selectedPlaylist == nil {
        Picker("Sort", selection: sortSelection) {
          if model.section == .songs {
            ForEach(LibraryModel.SongSort.allCases, id: \.self) {
              Text($0.rawValue).tag($0.rawValue)
            }
          } else {
            ForEach(LibraryModel.PlaylistSort.allCases, id: \.self) {
              Text($0.rawValue).tag($0.rawValue)
            }
          }
        }
        .frame(width: 130)
        Button {
          model.isAscending.toggle()
        } label: {
          Image(systemName: model.isAscending ? "arrow.up" : "arrow.down")
        }
        .accessibilityLabel(model.isAscending ? "Sort ascending" : "Sort descending")
      }
    }
  }

  @ViewBuilder private var content: some View {
    if model.isLoading {
      Spacer()
      ProgressView("Loading library")
      Spacer()
    } else if let error = model.errorMessage {
      stateMessage("Library unavailable", detail: error)
    } else if model.snapshot.songs.isEmpty && model.snapshot.playlists.isEmpty {
      stateMessage(
        "Your library is empty", detail: "Resolve a song or playlist to add it automatically.")
    } else if model.selectedPlaylist != nil {
      trackList(model.selectedPlaylistTracks)
    } else if model.section == .songs {
      if model.songs.isEmpty {
        stateMessage("No matching songs", detail: "Try a different search.")
      } else {
        songList
      }
    } else if model.playlists.isEmpty {
      stateMessage("No matching playlists", detail: "Try a different search.")
    } else {
      playlistList
    }
  }

  private var songList: some View {
    List(model.songs) { song in
      HStack {
        Button {
          Task { await player.playLibraryTracks([song.track]) }
        } label: {
          songLabel(song.track)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(song.track.title) now")
        Spacer()
        Button("Add") {
          player.addLibraryTracks([song.track])
          statusLine.show("Added \(song.track.title) to queue")
        }
        .accessibilityLabel("Add \(song.track.title) to queue")
        Button(role: .destructive) {
          songToRemove = song
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityLabel("Remove \(song.track.title)")
      }
      .contentShape(Rectangle())
      .accessibilityElement(children: .contain)
    }
    .listStyle(.plain)
  }

  private var playlistList: some View {
    List(model.playlists) { playlist in
      Button {
        model.selectedPlaylistID = playlist.id
        model.query = ""
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(playlist.title).font(Theme.archivo(13, .bold))
            Text(playlist.addedAt, style: .date)
              .font(Theme.mono(9)).foregroundStyle(Theme.dim)
          }
          Spacer()
          Text("\(playlist.tracks.count) songs")
            .font(Theme.mono(10)).foregroundStyle(Theme.dim)
          Image(systemName: "chevron.right")
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(playlist.title), \(playlist.tracks.count) songs")
    }
    .listStyle(.plain)
  }

  private func trackList(_ tracks: [Track]) -> some View {
    Group {
      if tracks.isEmpty {
        stateMessage("No matching songs", detail: "Try a different search.")
      } else {
        List(Array(tracks.enumerated()), id: \.element.id) { position, track in
          Button {
            Task { await player.playLibraryTracks([track]) }
          } label: {
            HStack {
              Text("\(position + 1)").frame(width: 24, alignment: .trailing)
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
              songLabel(track)
              Spacer()
              Button("Add") { player.addLibraryTracks([track]) }
                .accessibilityLabel("Add \(track.title) to queue")
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Play \(track.title)")
        }
        .listStyle(.plain)
      }
    }
  }

  private func songLabel(_ track: Track) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(track.title).font(Theme.archivo(12.5, .bold)).lineLimit(1)
      Text(track.artist ?? "Unknown artist")
        .font(Theme.mono(9)).foregroundStyle(Theme.dim).lineLimit(1)
    }
  }

  private func stateMessage(_ title: String, detail: String) -> some View {
    VStack(spacing: 6) {
      Spacer()
      Text(title).font(Theme.archivo(14, .bold))
      Text(detail).font(Theme.archivo(11, .medium)).foregroundStyle(Theme.dim)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var resultCount: String {
    let count = model.section == .songs ? model.songs.count : model.playlists.count
    return "\(count) \(model.section.rawValue)"
  }

  private var sortSelection: Binding<String> {
    Binding {
      model.section == .songs ? model.songSort.rawValue : model.playlistSort.rawValue
    } set: { value in
      if model.section == .songs, let sort = LibraryModel.SongSort(rawValue: value) {
        model.songSort = sort
      } else if let sort = LibraryModel.PlaylistSort(rawValue: value) {
        model.playlistSort = sort
      }
    }
  }
}
