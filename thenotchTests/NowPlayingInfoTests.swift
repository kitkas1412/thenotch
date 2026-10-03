//
//  NowPlayingInfoTests.swift
//  thenotchTests
//

import Foundation
import Testing
@testable import thenotch

struct NowPlayingInfoTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func track(
        _ source: NowPlayingInfo.Source = .spotify,
        title: String = "Song",
        playing: Bool = true,
        duration: TimeInterval? = 200,
        elapsed: TimeInterval? = 10,
        at date: Date? = nil
    ) -> NowPlayingInfo {
        NowPlayingInfo(
            source: source, title: title, artist: "Artist", album: "Album",
            isPlaying: playing, duration: duration, elapsed: elapsed, elapsedAt: date ?? now
        )
    }

    // MARK: Parsing

    @Test func parsesSpotifyNotification() throws {
        let info = try #require(NowPlayingInfo.fromSpotify([
            "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Player State": "Playing", "Duration": 215_000, "Playback Position": 42.5,
            "Track ID": "spotify:track:1",
        ], now: now))
        #expect(info == track(duration: 215, elapsed: 42.5))
    }

    @Test func parsesPausedSpotifyNotification() {
        let info = NowPlayingInfo.fromSpotify(["Name": "Song", "Player State": "Paused"], now: now)
        #expect(info?.isPlaying == false)
        #expect(info?.artist == "")
        #expect(info?.duration == nil)
    }

    @Test func stoppedSpotifyMeansNothingPlaying() {
        #expect(NowPlayingInfo.fromSpotify(["Player State": "Stopped"], now: now) == nil)
        #expect(NowPlayingInfo.fromSpotify(["Name": "Song", "Player State": "Stopped"], now: now) == nil)
    }

    @Test func parsesMusicNotificationWithoutPosition() throws {
        let info = try #require(NowPlayingInfo.fromMusic([
            "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Player State": "Playing", "Total Time": 200_000, "PersistentID": 123,
        ], now: now))
        #expect(info == track(.music, duration: 200, elapsed: nil))
    }

    @Test func stoppedMusicMeansNothingPlaying() {
        #expect(NowPlayingInfo.fromMusic(["Player State": "Stopped"], now: now) == nil)
    }

    // MARK: Elapsed time

    @Test func elapsedAdvancesWhilePlaying() {
        #expect(track(elapsed: 10).elapsed(at: now.addingTimeInterval(5)) == 15)
    }

    @Test func elapsedFreezesWhilePaused() {
        #expect(track(playing: false, elapsed: 10).elapsed(at: now.addingTimeInterval(5)) == 10)
    }

    @Test func elapsedIsClampedToDuration() {
        #expect(track(duration: 12, elapsed: 10).elapsed(at: now.addingTimeInterval(60)) == 12)
    }

    @Test func elapsedIsNilWhenUnknown() {
        #expect(track(elapsed: nil).elapsed(at: now) == nil)
    }

    // MARK: Merging updates

    @Test func musicUpdateKeepsPositionOfSameTrack() {
        let previous = track(.music, elapsed: 30, at: now)
        let paused = track(.music, playing: false, elapsed: nil, at: now.addingTimeInterval(4))
        #expect(paused.filledIn(from: previous).elapsed == 34)
    }

    @Test func artworkCarriesOverForSameTrack() {
        var previous = track()
        previous.artworkURL = URL(string: "https://i.scdn.co/image/abc")
        #expect(track().filledIn(from: previous).artworkURL == previous.artworkURL)
    }

    @Test func newTrackDoesNotInheritPreviousState() {
        var previous = track(.music, title: "Old", elapsed: 30)
        previous.artworkURL = URL(string: "https://example.com/a.jpg")
        let next = track(.music, title: "New", elapsed: nil).filledIn(from: previous)
        #expect(next.elapsed == nil)
        #expect(next.artworkURL == nil)
    }

    // MARK: Picking a source

    @Test func playingBeatsPaused() {
        let paused = track(.spotify, playing: false, at: now.addingTimeInterval(10))
        let playing = track(.music, playing: true, at: now)
        #expect(NowPlayingInfo.preferred([paused, playing])?.source == .music)
    }

    @Test func mostRecentWinsAmongEquals() {
        let older = track(.spotify, at: now)
        let newer = track(.music, at: now.addingTimeInterval(1))
        #expect(NowPlayingInfo.preferred([older, newer])?.source == .music)
        #expect(NowPlayingInfo.preferred([]) == nil)
    }
}
