//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit

public protocol VideoPlayerDelegate: AnyObject {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: VideoPlayer)
}

public class VideoPlayer: Dependencies {

    public let avPlayer: AVPlayer
    private let audioActivity: AudioActivity
    private let shouldLoop: Bool

    public var isMuted = false {
        didSet {
            avPlayer.volume = isMuted ? 0 : 1
        }
    }

    weak public var delegate: VideoPlayerDelegate?

    convenience public init(url: URL) {
        self.init(url: url, shouldLoop: false)
    }

    public init(url: URL, shouldLoop: Bool, shouldMixAudioWithOthers: Bool = false) {
        avPlayer = AVPlayer(url: url)
        audioActivity = AudioActivity(
            audioDescription: "[VideoPlayer] url:\(url)",
            behavior: shouldMixAudioWithOthers ? .playbackMixWithOthers : .playback
        )
        self.shouldLoop = shouldLoop

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToCompletion(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem
        )
    }

    deinit {
        endAudioActivity()
    }

    // MARK: Playback Controls

    public func endAudioActivity() {
        audioSession.endAudioActivity(audioActivity)
    }

    public func pause() {
        avPlayer.pause()
        endAudioActivity()
    }

    public func play() {
        let success = audioSession.startAudioActivity(audioActivity)
        assert(success)

        guard let item = avPlayer.currentItem else {
            owsFailDebug("video player item was unexpectedly nil")
            return
        }

        if item.currentTime() == item.duration {
            // Rewind for repeated plays, but only if it previously played to end.
            avPlayer.seek(to: CMTime.zero)
        }

        avPlayer.play()
    }

    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: CMTime.zero)
        endAudioActivity()
    }

    public func seek(to time: CMTime) {
        owsAssertBeta(avPlayer.rate == 0 || avPlayer.rate == 1)
        // Seek with a tolerance (or precision) of a hundredth of a second.
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: Self.preferredTimescale)
        avPlayer.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    public func rewind(_ seconds: TimeInterval) {
        let newTime = avPlayer.currentTime() - CMTime(seconds: seconds, preferredTimescale: Self.preferredTimescale)
        seek(to: newTime)
    }

    public func fastForward(_ seconds: TimeInterval) {
        let newTime = avPlayer.currentTime() + CMTime(seconds: seconds, preferredTimescale: Self.preferredTimescale)
        seek(to: newTime)
    }

    private var playbackRateToRestore: Float?

    // Specify negative rate to rewind.
    public func changePlaybackRate(to rate: Float) {
        owsAssertBeta(abs(rate) > 1)
        playbackRateToRestore = avPlayer.rate
        if rate < 0 {
            avPlayer.isMuted = true
        }
        avPlayer.rate = rate
    }

    public func restorePlaybackRate() {
        avPlayer.isMuted = false
        if let playbackRateToRestore {
            avPlayer.rate = playbackRateToRestore
            self.playbackRateToRestore = nil
        }
    }

    public var isPlaying: Bool {
        if let playbackRateToRestore {
            // For UI consistency's sake, if currently playing at non-default speed
            // return `true` if rewind/fast forward started when player was playing.
            return playbackRateToRestore == 1
        }
        return avPlayer.timeControlStatus == .playing
    }

    public var currentTimeSeconds: Double {
        return avPlayer.currentTime().seconds
    }

    private static var preferredTimescale: CMTimeScale { 1000 }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        playbackRateToRestore = nil
        delegate?.videoPlayerDidPlayToCompletion(self)
        if shouldLoop {
            avPlayer.seek(to: CMTime.zero)
            avPlayer.play()
        } else {
            endAudioActivity()
        }
    }
}
