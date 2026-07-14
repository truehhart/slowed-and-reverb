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
          LibrarySearchField(placeholder: "Search this playlist", text: $model.query)
        } else {
          controls
        }
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

  private func playlistHeader(_ playlist: LibraryPlaylist) -> some View {
    HStack(spacing: 10) {
      LibraryBackButton {
        model.selectedPlaylistID = nil
        model.query = ""
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(playlist.title)
          .font(Theme.archivo(14, .bold))
          .foregroundStyle(Theme.ivory)
          .lineLimit(1)
        Text(playlistSongCount(playlist))
          .font(Theme.mono(8.5))
          .foregroundStyle(Theme.labelDim)
      }
      Spacer()
      LibraryHeaderActionButton("Play All", systemImage: "play.fill") {
        Task {
          await player.playLibraryTracks(playlist.tracks)
          statusLine.show("Playing \(playlist.title)")
        }
      }
      .disabled(playlist.tracks.isEmpty)
      LibraryHeaderActionButton("Add All", systemImage: "text.badge.plus") {
        player.addLibraryTracks(playlist.tracks)
        statusLine.show("Added \(playlist.tracks.count) songs to queue")
      }
      .disabled(playlist.tracks.isEmpty)
      LibraryHeaderActionButton(
        "Remove", systemImage: "trash", isDestructive: true
      ) {
        playlistToRemove = playlist
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      SegmentedSelector(
        options: LibraryModel.Section.allCases.map { ($0.rawValue.capitalized, $0) },
        selection: $model.section
      )
      .frame(width: 180)
      LibrarySearchField(placeholder: searchPlaceholder, text: $model.query)
      LibrarySortMenu(options: sortOptions, selection: sortSelection)
        .frame(width: 118)
      LibraryDirectionButton(isAscending: sortDirection)
      LibraryCreatePlaylistButton()
        .frame(width: 132)
    }
  }

  @ViewBuilder private var content: some View {
    if model.isLoading {
      stateMessage("Loading library", detail: "Reading your saved music.", icon: "waveform")
    } else if let error = model.errorMessage {
      stateMessage("Library unavailable", detail: error, icon: "exclamationmark.triangle")
    } else if model.snapshot.songs.isEmpty && model.snapshot.playlists.isEmpty {
      stateMessage(
        "Your library is empty", detail: "Resolve a song or playlist to add it automatically.",
        icon: "music.note.house")
    } else if model.selectedPlaylist != nil {
      if model.selectedPlaylistSongs.isEmpty {
        if model.query.isEmpty {
          stateMessage(
            "This playlist is empty", detail: "There are no songs to show yet.",
            icon: "music.note.list")
        } else {
          stateMessage("No matching songs", detail: "Try a different search.")
        }
      } else {
        playlistSongCarousel
      }
    } else if model.section == .songs {
      if model.songs.isEmpty {
        stateMessage("No matching songs", detail: "Try a different search.")
      } else {
        songCarousel
      }
    } else if model.playlists.isEmpty {
      stateMessage("No matching playlists", detail: "Try a different search.")
    } else {
      playlistCarousel
    }
  }

  private var songCarousel: some View {
    LibraryCarousel(itemCount: model.songs.count) { index in
      let song = model.songs[index]
      LibrarySongCard(
        song: song,
        playAction: { play(song) },
        queueAction: { addToQueue(song) },
        removeAction: { songToRemove = song })
    }
    .frame(height: 220)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var playlistCarousel: some View {
    LibraryCarousel(itemCount: model.playlists.count) { index in
      let playlist = model.playlists[index]
      LibraryPlaylistCard(playlist: playlist) {
        model.selectedPlaylistID = playlist.id
        model.query = ""
      }
    }
    .frame(height: 220)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var playlistSongCarousel: some View {
    LibraryCarousel(itemCount: model.selectedPlaylistSongs.count) { index in
      let song = model.selectedPlaylistSongs[index]
      LibrarySongCard(
        song: song,
        playAction: { play(song) },
        queueAction: { addToQueue(song) },
        removeAction: nil)
    }
    .frame(height: 220)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func playlistSongCount(_ playlist: LibraryPlaylist) -> String {
    "\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "song" : "songs")"
  }

  private func play(_ song: LibrarySong) {
    Task {
      await player.playLibraryTracks([song.track])
      statusLine.show("Playing \(song.track.title)")
    }
  }

  private func addToQueue(_ song: LibrarySong) {
    player.addLibraryTracks([song.track])
    statusLine.show("Added \(song.track.title) to queue")
  }

  private func stateMessage(
    _ title: String, detail: String, icon: String = "magnifyingglass"
  ) -> some View {
    VStack(spacing: 6) {
      Spacer()
      Image(systemName: icon)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(Theme.burgundy)
        .padding(.bottom, 3)
      Text(title).font(Theme.archivo(14, .bold))
      Text(detail)
        .font(Theme.archivo(11, .medium))
        .foregroundStyle(Theme.dim)
        .multilineTextAlignment(.center)
        .lineLimit(3)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var searchPlaceholder: String {
    model.section == .songs ? "Search songs or artists" : "Search playlists"
  }

  private var sortOptions: [String] {
    if model.section == .songs {
      return LibraryModel.SongSort.allCases.map(\.rawValue)
    }
    return LibraryModel.PlaylistSort.allCases.map(\.rawValue)
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

  private var sortDirection: Binding<Bool> {
    Binding {
      model.section == .songs ? model.songSortAscending : model.playlistSortAscending
    } set: { value in
      if model.section == .songs {
        model.songSortAscending = value
      } else {
        model.playlistSortAscending = value
      }
    }
  }
}
