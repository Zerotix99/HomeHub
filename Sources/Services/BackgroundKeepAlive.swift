import Foundation
import AVFoundation

/// Hält die App auch bei gesperrtem Bildschirm oder im Hintergrund aktiv,
/// indem eine unhörbare, endlose Stille-Audiospur im `.mixWithOthers`-Modus abgespielt wird.
/// Dadurch unterbricht iOS die Netzwerk-Tasks und das Benachrichtigungs-Polling nicht!
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let silentWav = generateSilentWavData()
            audioPlayer = try AVAudioPlayer(data: silentWav)
            audioPlayer?.numberOfLoops = -1 // Endlose Wiederholung
            audioPlayer?.volume = 0.0 // 100% stumm, 0dB
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("[BackgroundKeepAlive] Lautlose Audio-Session gestartet - Hintergrund-Polling aktiv!")
        } catch {
            print("[BackgroundKeepAlive] Fehler beim Starten: \(error)")
        }
    }

    /// Generiert einen 1-sekündigen PCM-WAV-Header mit Nullen im Speicher
    private func generateSilentWavData() -> Data {
        var data = Data()
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = sampleRate
        let subChunk2Size = numSamples * Int32(channels) * Int32(bitsPerSample / 8)
        let chunkSize = 36 + subChunk2Size

        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        let subChunk1Size: Int32 = 16
        data.append(withUnsafeBytes(of: subChunk1Size.littleEndian) { Data($0) })
        let audioFormat: Int16 = 1 // PCM
        data.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        let byteRate = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = channels * (bitsPerSample / 8)
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: subChunk2Size.littleEndian) { Data($0) })
        data.append(Data(count: Int(subChunk2Size)))

        return data
    }
}
