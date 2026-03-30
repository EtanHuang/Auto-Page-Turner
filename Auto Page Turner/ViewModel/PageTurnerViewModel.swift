import Foundation
import AudioKit
import AVFoundation
import Combine
import PDFKit

struct AudioFeaturesContainer: Codable {
    let frame_rate: Double
    let features: [[Double]]
    let measure_map: [Int]
    let beat_map: [Int]
}

class PageTurnerViewModel: ObservableObject {
    // MARK: - Published Variables (Update the UI)
    @Published var isListening = false
    @Published var currentFrameIndex: Int = 0
    @Published var statusMessage = "Ready to load."
    @Published var currentAmplitude: Float = 0.0
    @Published var sensitivity: Float = 1.0
    @Published var currentChroma: [Double] = Array(repeating: 0.0, count: 12)
    @Published var currentMeasure: Int = 0
    @Published var currentBeat: Int = 0
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 0
    // MARK: - Internal Data
    // This will hold the massive list of features you generated in Python
    var previousChroma: [Double] = Array(repeating: 0.0, count: 12)
    var referenceFeatures: [[Double]] = []
    var measureMap: [Int] = []
    var beatMap: [Int] = []
    var frameRate: Double = 0.0
    var liveAudioHistory: [[Double]] = []
    let historySize = 7
    var pageBreaks: [Int] = []
    // MARK: - Audio Engine
    let engine = AudioEngine()
    var mic: AudioEngine.InputNode?
    var fftTap: FFTTap?
    var silentMixer: Mixer?
    
    func loadJSON(fileName: String) {
        // Now it uses the dynamic fileName instead of "waterfall_features_full"
        print(fileName)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            statusMessage = "❌ JSON file \(fileName) not found in Xcode!"
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let container = try JSONDecoder().decode(AudioFeaturesContainer.self, from: data)
            self.referenceFeatures = container.features
            self.measureMap = container.measure_map
            self.beatMap = container.beat_map
            self.frameRate = container.frame_rate
            statusMessage = "✅ Loaded \(referenceFeatures.count) frames of audio data."
            print(self.frameRate, referenceFeatures.count)
        } catch {
            statusMessage = "❌ Error decoding JSON: \(error.localizedDescription)"
        }
    }
    
    func loadPDFMetadata(url: URL) {
        if let document = PDFDocument(url: url) {
            self.totalPages = document.pageCount
        }
        print("Successfully loaded PDF with \(totalPages) pages")
    }
    
    func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 1.0 }
        
        // Dot Product
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        
        // Magnitudes
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        // Prevent division by zero
        if magA == 0 || magB == 0 { return 1.0 }
        
        // Similarity
        let similarity = dotProduct / (magA * magB)
        
        // Convert to Distance (1 - Similarity)
        return max(0.0, 1.0 - similarity)
    }
    
    func matrixCost(sequenceA: [[Double]], sequenceB: [[Double]]) -> Double {
        let n = sequenceA.count
        let m = sequenceB.count
        
        // 1. Initialize the Cost Matrix (D in the slide)
        // Size is (N+1) x (M+1) to handle the "zero buffer" edges
        var dp = Array(repeating: Array(repeating: Double.infinity, count: m + 1), count: n + 1)
        
        // 2. Base Case: D[0,0] = 0
        dp[0][0] = 0.0
        
        // 3. Calculate Cost Matrix
        for i in 1...n {
            for j in 1...m {
                // Calculate the distance between the two specific frames/vectors
                // This is the d(xi, yj) part from the slide
                let cost = cosineDistance(sequenceA[i - 1], sequenceB[j - 1])
                
                // Find the cheapest path from neighbors:
                // dp[i-1][j-1] -> Match (Diagonal)
                // dp[i-1][j]   -> Insertion (Top)
                // dp[i][j-1]   -> Deletion (Left)
                let minPrevious = min(dp[i - 1][j - 1], min(dp[i - 1][j], dp[i][j - 1]))
                
                dp[i][j] = cost + minPrevious
            }
        }
        
        // 4. Return the final accumulated cost (bottom-right corner)
        return dp[n][m]
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
    
    func updatePage() {
            // Finds the last index in pageBreaks that is less than or equal to currentMeasure
            if let pageIndex = pageBreaks.lastIndex(where: { $0 <= currentMeasure }) {
                self.currentPage = pageIndex + 1
            }
        }
    
    private func setupAudioEngine() {
        guard let input = engine.input else {
            statusMessage = "❌ No microphone detected."
            return
        }
        mic = input
        let hardwareFormat = engine.avEngine.inputNode.inputFormat(forBus: 0)
        print("🎤 Microphone Sample Rate: \(hardwareFormat.sampleRate) Hz")
        print("🎛️ Microphone Channels: \(hardwareFormat.channelCount)")
        if silentMixer == nil {
            let newMixer = Mixer(input)
            newMixer.volume = 0.0
            engine.output = newMixer
            self.silentMixer = newMixer
            print("🔊 Silent Audio Path Created")
        }
        
        // 1. Install the Tap on the microphone input
        fftTap = FFTTap(input, bufferSize: 8192) { fftData in
            
            // This block runs 60+ times a second!
            // We must hop back to the main thread to update UI
            DispatchQueue.main.async {
                self.processAudioData(fftData: fftData)
            }
        }
        
        // 2. Start the Tap
        fftTap?.start()

        do {
            try engine.start()
            isListening = true
            statusMessage = "🎤 Listening (Feedback Free)..."
            print("Audio Engine Started")
        } catch {
            statusMessage = "❌ Engine failed to start: \(error.localizedDescription)"
        }
    }

    // Add this helper function to your class
    func euclideanDistance(_ a: [Double], _ b: [Double]) -> Double {
        // Basic safety check: vectors must be same length (12)
        guard a.count == b.count else { return Double.greatestFiniteMagnitude }
        
        var sum: Double = 0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sqrt(sum)
    }

//    func dtwStep(liveChroma: [Double]) {
//        // 0. Safety Check: If map isn't loaded, don't do anything
//        guard !referenceFeatures.isEmpty else { return }
//        liveAudioHistory.append(liveChroma)
//        // Keep size fixed at 10
//        if liveAudioHistory.count > historySize {
//            liveAudioHistory.removeFirst()
//        }
//        if liveAudioHistory.count < historySize { return }
//        let isSilent = liveChroma.reduce(0, +) < 0.01
//        if isSilent {
//            return
//        }
//        // 1. Define the "Flashlight" (Search Window)
//        // We look a little bit behind (in case you dragged) and a bit ahead (in case you rushed)
//        let lookBack = 2
//        let lookAhead = 5
//        let startFrame = max(0, currentFrameIndex - lookBack)
//        let endFrame = min(referenceFeatures.count, currentFrameIndex + lookAhead)
//        
//        // 2. The Hunt: Find the best match inside the window
//        var bestIndex = currentFrameIndex
//        var bestCost = Double.greatestFiniteMagnitude
//        let idealNext = currentFrameIndex + 1
//        
////        if startFrame >= endFrame {
////            return
////        }
//
//        for i in startFrame..<endFrame {
//            let ref = referenceFeatures[i]
//            
//            // USE EUCLIDEAN DISTANCE
////            var dist = 0.0
////            for j in 0..<12 {
////                let d = liveChroma[j] - ref[j]
////                dist += d * d
////            }
////            dist = sqrt(dist)
////
////            
////            let frameDist = abs(i - idealNext)
////            let penalty = Double(frameDist) * 0.45
////
////            let cost = dist + penalty
////            
//            // USE MATRIX DISTANCE
//            let startRef = i - (historySize - 1)
//            let endRef = i + 1 // Swift ranges are exclusive at the end
//            
//            // Safety check (should be covered by startFrame logic, but good to have)
//            if startRef < 0 { continue }
//            
//            let refSequenceSlice = referenceFeatures[startRef..<endRef]
//            let refSequence = Array(refSequenceSlice)
//            
//            // NOW we can use Matrix Cost!
//            let rawDistance = matrixCost(sequenceA: liveAudioHistory, sequenceB: refSequence)
//
//            // Penalty Logic
//            let frameDist = abs(i - idealNext)
//            let penalty = Double(frameDist) * 0.01 // Keep small for DTW
//            
//            let cost = rawDistance + penalty
//
//            if cost < bestCost {
//                bestCost = cost
//                bestIndex = i
//            }
//        }
//        if bestCost > 5.0 { return }
//        let diff = bestIndex - currentFrameIndex
//        let clamped = max(-1, min(2, diff))   // allow slight back step, small forward jump
//
//        currentFrameIndex += clamped
//
//        if currentFrameIndex < measureMap.count {
//            currentMeasure = measureMap[currentFrameIndex]
//        }
//        if currentFrameIndex < beatMap.count {
//            currentBeat = beatMap[currentFrameIndex]
//        }
//    }
    
    func dtwStep(liveChroma: [Double]) {
        guard !referenceFeatures.isEmpty else { return }
        
        // --- 1. Update History ---
        liveAudioHistory.append(liveChroma)
        if liveAudioHistory.count > historySize {
            liveAudioHistory.removeFirst()
        }
        // We can't match until we have a full buffer of live audio
        if liveAudioHistory.count < historySize { return }
        
        // Optimization: Silence check
        let isSilent = liveChroma.reduce(0, +) < 0.01
        if isSilent { return }

        // --- 2. Define Window ---
        let lookBack = 0
        let lookAhead = 10
        let minValidIndex = historySize - 1
        
        let startFrame = max(minValidIndex, currentFrameIndex - lookBack)
        var calculatedEnd = currentFrameIndex + lookAhead
        calculatedEnd = max(calculatedEnd, minValidIndex + 2)
        let endFrame = min(referenceFeatures.count, calculatedEnd)
        
        if startFrame >= endFrame { return }

        var bestIndex = currentFrameIndex
        var bestCost = Double.greatestFiniteMagnitude
        
        let matchThreshold = 4.5
    
        // Iterate BACKWARDS from the furthest future frame
        for i in (startFrame..<endFrame).reversed() {
            let startRef = i - (historySize - 1)
            let endRef = i + 1
            
            let refSequenceSlice = referenceFeatures[startRef..<endRef]
            let refSequence = Array(refSequenceSlice)
            
            let rawDistance = matrixCost(sequenceA: liveAudioHistory, sequenceB: refSequence)
            
            // Still apply a small penalty for big jumps so we don't pick garbage
            // But keep it small so valid jumps are possible.
            let jumpDistance = i - (currentFrameIndex + 1)
            let penalty = Double(abs(jumpDistance)) * 0.05
            let cost = rawDistance + penalty

            // STRATEGY A: The "Good Enough" Check
            // If this future frame is a solid match, take it and STOP.
            // This guarantees we pick the furthest valid point.
            if cost < matchThreshold {
                bestIndex = i
                bestCost = cost
                break
            }
            
            // STRATEGY B: The Fallback
            // If we haven't found a "good enough" match yet, keep track of the absolute best
            // just in case we need to fall back to standard DTW.
            if cost < bestCost {
                bestCost = cost
                bestIndex = i
            }
        }
        
        // --- Threshold Tuning ---
        print("\(String(format: "%.2f", bestCost))")
        if bestCost > 8.0{ return }
        
        let diff = bestIndex - currentFrameIndex
        let maxJump = (currentFrameIndex == 0) ? historySize : 5
        let clamped = max(-1, min(maxJump, diff))
        
        currentFrameIndex += clamped

        if currentFrameIndex < measureMap.count {
            currentMeasure = measureMap[currentFrameIndex]
        }
        if currentFrameIndex < beatMap.count {
            currentBeat = beatMap[currentFrameIndex]
        }
        if currentFrameIndex < measureMap.count {
            currentMeasure = measureMap[currentFrameIndex]
            updatePage()
        }
    }
    
    func processAudioData(fftData: [Float]) {
        // 1. SKIP THE GHOSTS (DC Offset)
        // We drop the first 4 bins (very low freq / 0Hz noise)
        // This ensures we are measuring actual audio, not hardware artifacts.
        let meaningfulData = fftData.dropFirst(8)
        
        // 2. Get the loudest REMAINING frequency
        let maxVal = meaningfulData.max() ?? 0.0
        let rawNoiseFloor: Float = 0.06
        if maxVal < rawNoiseFloor {
            DispatchQueue.main.async {
                // Fade out visuals quickly
                self.currentAmplitude = 0.0
                self.currentChroma = self.currentChroma.map { $0 * 0.6 }
                self.statusMessage = "..."
            }
            return
        }
        let sum = meaningfulData.reduce(0, +)
        let avgVal = sum / Float(meaningfulData.count)
        
        // Calculate Ratio: How much louder is the Peak compared to the Average?
        // Breathing: Peak is maybe 2x the average (Flat graph)
        // Music: Peak is 10x-50x the average (Spiky graph)
        let snr = maxVal / avgVal
        
        // If the spike isn't at least 4x taller than the floor, it's just noise.
        if snr < 4.0 {
            DispatchQueue.main.async {
                self.statusMessage = "💨 Ignoring Noise..."
                // Don't update visuals, just return
            }
            return
        }
        // 3. Update the UI
        // I lowered the multiplier to 1.5 so it's less sensitive
        let amplifiedVal = maxVal * sensitivity
        self.currentAmplitude = min(amplifiedVal, 1.0)
        
        if amplifiedVal > 0.5 {
            let newChroma = calculateChroma(fftData: fftData)
            self.currentChroma = newChroma
            self.dtwStep(liveChroma: newChroma)
        } else {
            // If silence, fade the bars out slowly
            self.currentChroma = self.currentChroma.map { $0 * 0.7 }
        }
        
        if amplifiedVal > 0.1 {
            self.statusMessage = "🎵 I hear music!"
        } else {
            self.statusMessage = "🎤 Listening..."
        }
    }

    func calculateChroma(fftData: [Float]) -> [Double] {
        if fftData.isEmpty { return Array(repeating: 0.0, count: 12) }
        let sampleRate = self.engine.avEngine.inputNode.inputFormat(forBus: 0).sampleRate
        //engine.avEngine.inputNode.inputFormat(forBus: 0)
        let fft = fftData
        let n = fft.count
        let binHz = sampleRate / Double(n * 2)

        // 1. RMS/Noise Gate
        let rms = sqrt(fft.reduce(0) { $0 + $1 * $1 } / Float(n))
        if rms < 0.01 { return Array(repeating: 0.0, count: 12) }

        var chroma = [Double](repeating: 0.0, count: 12)

        // 2. Process every bin with sub-bin accuracy
        for i in 1..<(n-1) {
            let mag = Double(fft[i])
            
            // Parabolic Interpolation: Finding the true frequency peak between bins
            // This is vital for low pitches where notes are spaced tighter than bins.
            let alpha = Double(fft[i - 1])
            let beta = Double(fft[i])
            let gamma = Double(fft[i + 1])
            
            // Calculate the sub-bin offset
            let denominator = alpha - 2.0 * beta + gamma
            let offset = (denominator == 0) ? 0 : 0.5 * (alpha - gamma) / denominator
            let refinedIndex = Double(i) + offset
            let freq = refinedIndex * binHz
            
            // Limit range to piano spectrum
            if freq < 27.5 || freq > 4186.0 { continue }

            // 3. Frequency to MIDI conversion
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            let note = Int(round(midi))
            let pc = (note % 12 + 12) % 12
            
            var weight = 1.0
            if freq < 100 {
                weight = 0.8
            } else if freq >= 100 && freq < 260 {
                weight = 1.2
            }
            chroma[pc] += mag * weight
        }
        // 5. Normalization
        let maxVal = chroma.max() ?? 0
        print("Max Chroma Level: \(maxVal)")
        if maxVal < 1.2 { return Array(repeating: 0.0, count: 12) }
        let normalized = chroma.map { $0 / maxVal }
        
        // Arzt-inspired Temporal Smoothing (Alpha blending)
        let sharpened = normalized.map { $0 * $0 }
        let smoothed = zip(previousChroma, sharpened).map { (prev, current) in
            return (prev * 0.2) + (current * 0.8)
        }
        self.previousChroma = smoothed
        return smoothed
    }

    func stopListening() {
        // 1. Stop the audio engine
        engine.stop()
        engine.avEngine.inputNode.removeTap(onBus: 0)
        fftTap = nil
        // 3. Reset the UI State
        DispatchQueue.main.async {
            self.isListening = false
            self.statusMessage = "Stopped & Reset."
            
            // Reset Progress
            self.currentFrameIndex = 0
            self.currentMeasure = 0
            self.currentBeat = 0
            
            // Reset Audio Visuals
            self.currentAmplitude = 0.0
            self.currentChroma = Array(repeating: 0.0, count: 12)
            self.previousChroma = Array(repeating: 0.0, count: 12)
        }
    }
}
