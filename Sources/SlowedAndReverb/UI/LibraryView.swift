import SwiftUI

struct LibraryView: View {
  @Environment(PlayerModel.self) private var player
  @Bindable var model: LibraryModel
  @State private var isSortMenuExpanded = false

  let statusLine: StatusLine

  var body: some View {
    ModuleBox("library") {
      VStack(spacing: 10) {
        if let playlist = model.selectedPlaylist {
          playlistHeader(playlist)
        } else {
          controls
            .zIndex(1)
        }
        ZStack {
          content
          if isSortMenuExpanded {
            Color.black.opacity(0.001)
              .contentShape(Rectangle())
              .onTapGesture { isSortMenuExpanded = false }
          }
        }
      }
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
      LibrarySearchField(placeholder: "Search this playlist", text: $model.query)
      LibraryHeaderActionButton("Play All", systemImage: "play.fill") {
        Task {
          await player.playLibraryTracks(playlist.tracks)
          statusLine.clear()
        }
      }
      .disabled(playlist.tracks.isEmpty)
      LibraryHeaderActionButton("Queue All", systemImage: "text.badge.plus") {
        player.addLibraryTracks(playlist.tracks)
        statusLine.flash("Queued \(playlist.tracks.count) songs")
      }
      .disabled(playlist.tracks.isEmpty)
      HoldToDeleteButton(
        "Remove",
        accessibilityLabel: "Remove \(playlist.title)",
        help: "Hold to remove playlist"
      ) {
        remove(playlist)
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
      .simultaneousGesture(TapGesture().onEnded { isSortMenuExpanded = false })
      LibrarySearchField(placeholder: searchPlaceholder, text: $model.query)
        .simultaneousGesture(TapGesture().onEnded { isSortMenuExpanded = false })
      LibrarySortMenu(
        options: sortOptions,
        selection: sortSelection,
        isExpanded: $isSortMenuExpanded
      )
      .frame(width: 118)
      LibraryDirectionButton(isAscending: sortDirection)
        .simultaneousGesture(TapGesture().onEnded { isSortMenuExpanded = false })
      LibraryCreatePlaylistButton()
        .frame(width: 132)
        .simultaneousGesture(TapGesture().onEnded { isSortMenuExpanded = false })
    }
  }

  @ViewBuilder private var content: some View {
    if model.isLoading && !model.hasLoaded {
      stateMessage("Loading library", detail: "Reading your saved music.", icon: "waveform")
    } else if let error = model.errorMessage {
      stateMessage("Library unavailable", detail: error, icon: "exclamationmark.triangle")
    } else if model.snapshot.songs.isEmpty && model.snapshot.playlists.isEmpty {
      stateMessage(
        "Your library is empty", detail: "Resolve a song or playlist to add it automatically.",
        icon: "music.note.house")
    } else if model.selectedPlaylist != nil {
      let songs = model.selectedPlaylistSongs
      if songs.isEmpty {
        if model.query.isEmpty {
          stateMessage(
            "This playlist is empty", detail: "There are no songs to show yet.",
            icon: "music.note.list")
        } else {
          stateMessage("No matching songs", detail: "Try a different search.")
        }
      } else {
        playlistSongCarousel(songs)
      }
    } else if model.section == .songs {
      let songs = model.songs
      if songs.isEmpty {
        stateMessage("No matching songs", detail: "Try a different search.")
      } else {
        songCarousel(songs)
      }
    } else {
      let playlists = model.playlists
      if playlists.isEmpty {
        stateMessage("No matching playlists", detail: "Try a different search.")
      } else {
        playlistCarousel(playlists)
      }
    }
  }

  private func songCarousel(_ songs: [LibrarySong]) -> some View {
    LibraryCarousel(items: songs) { song in
      LibrarySongCard(
        song: song,
        playAction: { play(song) },
        queueAction: { addToQueue(song) },
        removeAction: { remove(song) })
    }
    .frame(height: 290)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func playlistCarousel(_ playlists: [LibraryPlaylist]) -> some View {
    LibraryCarousel(items: playlists) { playlist in
      LibraryPlaylistCard(playlist: playlist) {
        model.selectedPlaylistID = playlist.id
        model.query = ""
      }
    }
    .frame(height: 290)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func playlistSongCarousel(_ songs: [LibrarySong]) -> some View {
    LibraryCarousel(items: songs) { song in
      LibrarySongCard(
        song: song,
        playAction: { play(song) },
        queueAction: { addToQueue(song) },
        removeAction: nil)
    }
    .frame(height: 290)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func playlistSongCount(_ playlist: LibraryPlaylist) -> String {
    "\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "song" : "songs")"
  }

  private func play(_ song: LibrarySong) {
    Task {
      await player.playLibraryTracks([song.track])
      statusLine.clear()
    }
  }

  private func addToQueue(_ song: LibrarySong) {
    player.addLibraryTracks([song.track])
    statusLine.flash("Added \(song.track.title) to queue")
  }

  private func remove(_ song: LibrarySong) {
    Task {
      let removed = await model.removeSong(id: song.id, using: player)
      if removed {
        statusLine.flash("Removed \(song.track.title)")
      } else {
        statusLine.show("Could not remove song", isError: true)
      }
    }
  }

  private func remove(_ playlist: LibraryPlaylist) {
    Task {
      let removed = await model.removePlaylist(id: playlist.id, using: player)
      if removed {
        statusLine.flash("Removed \(playlist.title)")
      } else {
        statusLine.show("Could not remove playlist", isError: true)
      }
    }
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
    return "Search"
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
