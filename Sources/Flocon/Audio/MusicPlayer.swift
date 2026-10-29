import AVFoundation
import AudioToolbox

enum MusicVolume: Int, CaseIterable {
    case whisper, soft, medium

    var title: String { ["Whisper", "Soft", "Medium"][rawValue] }
    /// Linear gain on the player's own mixer; the system volume is never touched.
    var level: Float { [0.08, 0.16, 0.3][rawValue] }
}

/// One instrument in an ensemble: a General MIDI program playing the upper or lower voice,
/// an octave shift and a velocity.
private struct Voice {
    let program: UInt8
    let plays: KeyPath<Carol, [Carol.Note]>
    let shift: Int
    let velocity: UInt32
}

/// Plays the carols quietly through the macOS built-in General MIDI sounds, so no samples are bundled.
/// Nothing is created until the first time it is asked to play, and the audio device is released
/// again whenever it stops.
/// Main-thread only, like the rest of the app.
final class MusicPlayer {
    static let bankURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    /// Each carol is played once with every ensemble, so a long loop keeps changing colour.
    private static let ensembles: [[Voice]] = [
        // Music box with harp and soft strings underneath.
        [Voice(program: 10, plays: \.upper, shift: 0, velocity: 64),
         Voice(program: 46, plays: \.lower, shift: 0, velocity: 44),
         Voice(program: 48, plays: \.lower, shift: 0, velocity: 26)],
        // Celesta and glockenspiel sparkle over strings and harp.
        [Voice(program: 8, plays: \.upper, shift: 0, velocity: 60),
         Voice(program: 9, plays: \.upper, shift: 12, velocity: 22),
         Voice(program: 48, plays: \.lower, shift: 0, velocity: 34),
         Voice(program: 46, plays: \.lower, shift: 0, velocity: 38)],
        // Flute and music box over a harp and strings bed.
        [Voice(program: 73, plays: \.upper, shift: 0, velocity: 46),
         Voice(program: 10, plays: \.upper, shift: 0, velocity: 48),
         Voice(program: 46, plays: \.lower, shift: -12, velocity: 44),
         Voice(program: 48, plays: \.lower, shift: 0, velocity: 30)],
    ]
    /// MIDI channels in use; channel 9 (index) is percussion in General MIDI.
    private static let channels = (0..<16).filter { $0 != 9 }
    /// Silence between carols.
    private static let pause = 4.0
    static var isAvailable: Bool { FileManager.default.fileExists(atPath: bankURL.path) }

    var volume: Float = MusicVolume.soft.level {
        didSet { if wantsToPlay { engine?.mainMixerNode.outputVolume = volume } }
    }
    private(set) var wantsToPlay = false
    private var engine: AVAudioEngine?
    private var synth: AVAudioUnitMIDIInstrument?
    private var sequencer: AVAudioSequencer?
    private var next: Timer?
    private var fade: Timer?
    private var index = 0
    private var generation = 0
    private let loader = DispatchQueue(label: "flocon.music", qos: .utility)
    private var configObserver: NSObjectProtocol?

    func setPlaying(_ playing: Bool) {
        guard playing != wantsToPlay else { return }
        wantsToPlay = playing
        playing ? start() : stop()
    }

    private func start() {
        guard Self.isAvailable, !Carol.all.isEmpty else { wantsToPlay = false; return }
        if engine != nil { return begin() }
        // Loading the sound bank takes seconds, so it happens off the main thread.
        generation += 1
        let generation = generation
        loader.async { [weak self] in
            let built = Result { try MusicPlayer.makeEngine() }
            DispatchQueue.main.async {
                guard let self, generation == self.generation, self.wantsToPlay else { return }
                switch built {
                case .success(let (engine, synth)):
                    self.install(engine, synth)
                    self.begin()
                case .failure:
                    self.wantsToPlay = false
                }
            }
        }
    }

    private func begin() {
        guard let engine, let carol = Carol.all[safe: index % Carol.all.count] else { return }
        do {
            engine.mainMixerNode.outputVolume = 0
            if !engine.isRunning { try engine.start() }
            for (voice, channel) in zip(Self.ensembles.flatMap { $0 }, Self.channels) {
                synth?.sendController(0, withValue: 0, onChannel: UInt8(channel))
                synth?.sendController(32, withValue: 0, onChannel: UInt8(channel))
                synth?.sendProgramChange(voice.program, onChannel: UInt8(channel))
            }
            try play(carol, on: engine)
            ramp(to: volume, then: nil)
        } catch {
            wantsToPlay = false
            tearDown()
        }
    }

    private func stop() {
        generation += 1
        next?.invalidate()
        next = nil
        guard engine?.isRunning == true else { return tearDown() }
        ramp(to: 0) { [weak self] in
            guard let self, !self.wantsToPlay else { return }
            self.tearDown()
        }
    }

    private static func makeEngine() throws -> (AVAudioEngine, AVAudioUnitMIDIInstrument) {
        let engine = AVAudioEngine()
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 40
        engine.attach(reverb)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        // One multi-timbral synth, a channel per voice: several samplers sharing the same bank file silence each other.
        let description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_MIDISynth,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let synth = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        engine.attach(synth)
        engine.connect(synth, to: reverb, format: nil)
        var url = bankURL as CFURL
        let status = withUnsafePointer(to: &url) {
            AudioUnitSetProperty(synth.audioUnit, AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                 kAudioUnitScope_Global, 0, $0, UInt32(MemoryLayout<CFURL>.size))
        }
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return (engine, synth)
    }

    private func install(_ engine: AVAudioEngine, _ synth: AVAudioUnitMIDIInstrument) {
        self.engine = engine
        self.synth = synth
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.wantsToPlay else { return }
            self.tearDown()
            self.start()
        }
    }

    private func play(_ carol: Carol, on engine: AVAudioEngine) throws {
        let sequencer = AVAudioSequencer(audioEngine: engine)
        let track = sequencer.createAndAppendTrack()
        track.destinationAudioUnit = synth
        var channel = 0
        for (pass, ensemble) in Self.ensembles.enumerated() {
            let offset = Double(pass) * carol.totalBeats
            for voice in ensemble {
                for note in carol[keyPath: voice.plays] {
                    track.addEvent(AVMIDINoteEvent(channel: UInt32(Self.channels[channel]), key: UInt32(Int(note.pitch) + voice.shift),
                                                   velocity: voice.velocity, duration: note.beats), at: offset + note.start)
                }
                channel += 1
            }
        }
        let total = carol.totalBeats * Double(Self.ensembles.count)
        track.lengthInBeats = total
        sequencer.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: carol.bpm), at: 0)
        sequencer.prepareToPlay()
        try sequencer.start()
        self.sequencer = sequencer
        let length = sequencer.seconds(forBeats: total)
        next = Timer.scheduledTimer(withTimeInterval: length + Self.pause, repeats: false) { [weak self] _ in
            guard let self, self.wantsToPlay, let engine = self.engine else { return }
            self.index += 1
            self.sequencer?.stop()
            if let carol = Carol.all[safe: self.index % Carol.all.count] { try? self.play(carol, on: engine) }
        }
    }

    private func ramp(to target: Float, then done: (() -> Void)?) {
        fade?.invalidate()
        guard let mixer = engine?.mainMixerNode else { return done?() ?? () }
        let from = mixer.outputVolume
        let steps = 24
        var step = 0
        fade = Timer.scheduledTimer(withTimeInterval: 1.5 / Double(steps), repeats: true) { [weak self] timer in
            step += 1
            mixer.outputVolume = from + (target - from) * Float(step) / Float(steps)
            if step >= steps {
                timer.invalidate()
                self?.fade = nil
                done?()
            }
        }
    }

    private func tearDown() {
        generation += 1
        next?.invalidate()
        fade?.invalidate()
        next = nil
        fade = nil
        sequencer?.stop()
        sequencer = nil
        engine?.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        synth = nil
        engine = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
