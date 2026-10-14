import Foundation

/// The start and finish sounds, synthesised so there are no audio assets: two quiet, low
/// sine notes with a slow fade-in and a long fade-out.
public enum Chime {
    public struct Note: Sendable {
        public var from: Double
        public var to: Double
        public var seconds: Double

        public init(_ hertz: Double, to target: Double? = nil, seconds: Double) {
            from = hertz
            to = target ?? hertz
            self.seconds = seconds
        }
    }

    /// C5 rising to G5: listening has started.
    public static let start = [Note(523, seconds: 0.09), Note(784, seconds: 0.22)]
    /// G5 falling to C5: the text is in.
    public static let finish = [Note(784, seconds: 0.09), Note(523, seconds: 0.24)]

    public static let sampleRate = 44_100

    /// 16-bit mono PCM samples. `volume` is the peak level from 0 to 1.
    public static func samples(_ notes: [Note], volume: Double = 0.12) -> [Int16] {
        var output: [Int16] = []
        var phase = 0.0
        for note in notes {
            let count = Int(note.seconds * Double(sampleRate))
            for index in 0..<count {
                let progress = Double(index) / Double(max(count - 1, 1))
                let hertz = note.from + (note.to - note.from) * progress
                phase += 2 * .pi * hertz / Double(sampleRate)
                // 15 ms fade-in, then an exponential fade so the note never clicks off.
                let attack = min(1, Double(index) / (0.015 * Double(sampleRate)))
                let envelope = attack * exp(-4 * progress)
                output.append(Int16((sin(phase) * envelope * volume * Double(Int16.max)).rounded()))
            }
        }
        return output
    }

    /// The notes as a WAV file in memory, ready for NSSound or AVAudioPlayer.
    public static func wav(_ notes: [Note], volume: Double = 0.12) -> Data {
        let pcm = samples(notes, volume: volume)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))  // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in pcm { append(sample) }
        return data
    }
}
