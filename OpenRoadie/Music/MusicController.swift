import Foundation
import MediaPlayer

/// DJ Roadie: controls the system Music player, so play/pause/skip work on
/// whatever the Music app is doing, and "play X" queues from the user's
/// library. Playback happens in the Music app's process — no audio-session
/// fight with voice.
@MainActor
final class MusicController {
    private let player = MPMusicPlayerController.systemMusicPlayer

    func handle(action: String, query: String?) async -> String {
        let normalized = action.lowercased().trimmingCharacters(in: .whitespaces)
        let searchTerm = query?.trimmingCharacters(in: .whitespaces) ?? ""

        switch normalized {
        case "play" where searchTerm.isEmpty, "resume":
            player.play()
            return "Resumed playback. Confirm briefly."
        case "play":
            return await playFromLibrary(matching: searchTerm)
        case "pause", "stop":
            player.pause()
            return "Paused. Confirm briefly."
        case "next", "skip":
            player.skipToNextItem()
            return "Skipped to the next track. Confirm briefly."
        case "previous", "back":
            player.skipToPreviousItem()
            return "Went back a track. Confirm briefly."
        case "nowplaying", "now_playing", "current":
            guard await Self.requestLibraryAccess() else {
                return "Music library access is off — the driver can enable it in Settings → Privacy → Media & Apple Music."
            }
            return nowPlaying()
        default:
            return "Unknown music action \"\(action)\". Valid: play, pause, next, previous, nowplaying."
        }
    }

    func nowPlaying() -> String {
        if let item = player.nowPlayingItem {
            let title = item.title ?? "Unknown title"
            let artist = item.artist ?? "unknown artist"
            return "Now playing: \(title) by \(artist)."
        }
        return player.playbackState == .playing
            ? "Audio is playing, but from an app I can't see into (like Spotify) — I can only read the Apple Music app."
            : "Nothing is playing in the Music app."
    }

    private func playFromLibrary(matching term: String) async -> String {
        guard await Self.requestLibraryAccess() else {
            return "Music library access is off — the driver can enable it in Settings → Privacy → Media & Apple Music."
        }

        let items = Self.searchLibrary(term)
        guard !items.isEmpty else {
            return "No songs matching \"\(term)\" in the music library. Say so — do not pretend to play it."
        }

        player.setQueue(with: MPMediaItemCollection(items: items))
        player.play()
        let first = items[0]
        let title = first.title ?? "Unknown title"
        let artist = first.artist ?? "unknown artist"
        return items.count == 1
            ? "Playing \(title) by \(artist)."
            : "Playing \(title) by \(artist), with \(items.count - 1) more matches queued."
    }

    /// Title, artist, and album matches, deduped, title matches first.
    private static func searchLibrary(_ term: String) -> [MPMediaItem] {
        var seen = Set<MPMediaEntityPersistentID>()
        var results: [MPMediaItem] = []
        for property in [MPMediaItemPropertyTitle, MPMediaItemPropertyArtist, MPMediaItemPropertyAlbumTitle] {
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(
                value: term, forProperty: property, comparisonType: .contains
            ))
            for item in query.items ?? [] where !seen.contains(item.persistentID) {
                seen.insert(item.persistentID)
                results.append(item)
            }
        }
        return Array(results.prefix(50))
    }

    /// nonisolated: the authorization callback arrives on a background queue.
    private nonisolated static func requestLibraryAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
