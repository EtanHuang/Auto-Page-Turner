import Foundation
import AudioKit // Make sure this is imported!
import AVFoundation
import Combine

class PageTurnerViewModel: ObservableObject {
    // MARK: - Published Variables (Update the UI)
    @Published var isListening = false
    @Published var currentFrameIndex: Int = 0
    @Published var statusMessage = "Ready to load."
    @Published var currentAmplitude: Float = 0.0
    @Published var sensitivity: Float = 5.0
    @Published var currentChroma: [Double] = Array(repeating: 0.0, count: 12)
    // MARK: - Internal Data
    // This will hold the massive list of features you generated in Python
    var referenceFeatures: [[Double]] = []
    
    // MARK: - Audio Engine
    let engine = AudioEngine()
    var mic: AudioEngine.InputNode?
    var fftTap: FFTTap?
    
    init() {
        // Automatically try to load the file when the app starts
        loadJSON()
    }
    
    // 1. THE BRAIN: Load the JSON "buckets"
    func loadJSON() {
        // Look for "ballade1_features.json" in the app bundle
        guard let url = Bundle.main.url(forResource: "ballade1_features", withExtension: "json") else {
            statusMessage = "❌ JSON file not found in Xcode!"
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            // Decode the list of lists [[0.1, 0.5...], [0.2, ...]]
            referenceFeatures = try JSONDecoder().decode([[Double]].self, from: data)
            statusMessage = "✅ Loaded \(referenceFeatures.count) frames of audio data."
        } catch {
            statusMessage = "❌ Error decoding JSON: \(error.localizedDescription)"
        }
    }
    
    // 2. THE EARS: Start the Microphone
    func startListening() {
        // Request permission from iOS
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                // We must run UI updates on the main thread
                DispatchQueue.main.async {
                    self.setupAudioEngine()
                }
            } else {
                DispatchQueue.main.async {
                    self.statusMessage = "🚫 Microphone permission denied."
                }
            }
        }
    }
    
    private func setupAudioEngine() {
        guard let input = engine.input else {
            statusMessage = "❌ No microphone detected."
            return
        }
        mic = input
        
        // 1. Install the Tap on the microphone input
        // "bufferSize: 1024" means it grabs 1024 frequency bins at a time
        fftTap = FFTTap(input, bufferSize: 1024) { fftData in
            
            // This block runs 60+ times a second!
            // We must hop back to the main thread to update UI
            DispatchQueue.main.async {
                self.processAudioData(fftData: fftData)
            }
        }
        
        // 2. Start the Tap
        fftTap?.start()
        
        // Connect the mic to the main output (muted so you don't hear feedback)
        // In the real app, we will attach an Analyzer Tap here instead of outputting audio
        let mixer = Mixer(input)
            mixer.volume = 0
            
            // Connect the silent mixer to the output
            engine.output = mixer
            
            do {
                try engine.start()
                isListening = true
                statusMessage = "🎤 Listening (Feedback Free)..."
                print("Audio Engine Started")
            } catch {
                statusMessage = "❌ Engine failed to start: \(error.localizedDescription)"
            }
    }
    func processAudioData(fftData: [Float]) {
            // 1. SKIP THE GHOSTS (DC Offset)
            // We drop the first 4 bins (very low freq / 0Hz noise)
            // This ensures we are measuring actual audio, not hardware artifacts.
            let meaningfulData = fftData.dropFirst(4)
            
            // 2. Get the loudest REMAINING frequency
            let maxVal = meaningfulData.max() ?? 0.0
            
            // 3. Update the UI
            // I lowered the multiplier to 1.5 so it's less sensitive
            let amplifiedVal = maxVal * sensitivity
            self.currentAmplitude = min(amplifiedVal, 1.0)
            
            if amplifiedVal > 0.1 {
                self.currentChroma = calculateChroma(fftData: fftData)
            } else {
                // If silence, fade the bars out slowly
                self.currentChroma = self.currentChroma.map { $0 * 0.8 }
            }
        
            if amplifiedVal > 0.5 { // Lowered threshold slightly
                self.statusMessage = "🎵 I hear music!"
            } else {
                 self.statusMessage = "🎤 Listening..."
            }
        }
    func calculateChroma(fftData: [Float]) -> [Double] {
            var tempChroma = [Double](repeating: 0.0, count: 12)
            
            // AudioKit FFT usually returns frequencies up to Nyquist (SampleRate / 2)
            // Assuming 44100Hz Sample Rate and 1024 bins:
            // Resolution is approx 21.5 Hz per bin.
            let binResolution = 44100.0 / Double(fftData.count * 2)
            
            for (index, magnitude) in fftData.enumerated() {
                // Skip low rumbles (indices 0-10) and super high squeaks (indices > 500)
                if index < 10 || index > 500 { continue }
                
                // 1. Calculate Frequency of this bin
                let frequency = Double(index) * binResolution
                
                // 2. Convert Frequency to MIDI Note Number
                // Formula: 69 + 12 * log2(freq / 440)
                let midiNote = 69 + 12 * log2(frequency / 440.0)
                
                // 3. Get Pitch Class (0-11)
                // We round to the nearest note
                let pitchClass = Int(round(midiNote).truncatingRemainder(dividingBy: 12))
                
                // Fix negative results from modulo logic
                let cleanPitchClass = pitchClass < 0 ? pitchClass + 12 : pitchClass
                
                // 4. Add magnitude to the bucket
                tempChroma[cleanPitchClass] += Double(magnitude)
            }
            
            // 5. Normalize (Scale so the max value is 1.0)
            if let maxVal = tempChroma.max(), maxVal > 0 {
                return tempChroma.map { min(($0 / maxVal) * Double(sensitivity), 1.0) }
            }
            
            return tempChroma
        }
    func stopListening() {
            // 1. Stop the audio engine
            engine.stop()
            
            // 2. Remove the "Spy" (Tap)
            // If we don't do this, the app will crash when we try to add it again later.
            engine.avEngine.inputNode.removeTap(onBus: 0)
            fftTap = nil // Clear the variable
            
            // 3. Reset the UI State 
            DispatchQueue.main.async {
                self.isListening = false
                self.statusMessage = "Stopped."
                self.currentAmplitude = 0.0
                self.currentChroma = Array(repeating: 0.0, count: 12) // Clear the bars
            }
        }
}
