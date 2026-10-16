// HistoryAudioPlayer.swift
// VocaMac
//
// Plays back the audio saved with a history entry, one recording at a time.

import AVFoundation
import Foundation

/// Plays one history recording at a time.
@MainActor
final class HistoryAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HistoryAudioPlayer()

    @Published private(set) var playingURL: URL?
    private var player: AVAudioPlayer?

    /// Plays `url`, or stops it when it is the recording already playing.
    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            playingURL = url
        } catch {
            VocaLogger.warning(.history, "Could not play recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
