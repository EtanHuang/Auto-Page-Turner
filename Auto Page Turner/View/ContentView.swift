import SwiftUI

struct ContentView: View {
    // Connect to the ViewModel
    @StateObject var viewModel = PageTurnerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Status Icon
            Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(viewModel.isListening ? .green : .red)
            
            // Status Text
            Text(viewModel.statusMessage)
                .multilineTextAlignment(.center)
                .padding()
            
            // Stats
            if !viewModel.referenceFeatures.isEmpty {
                Text("Reference: \(viewModel.referenceFeatures.count) frames loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading) {
                Text("Microphone Input Level")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                ZStack(alignment: .leading) {
                    // 1. Grey Background Bar
                    RoundedRectangle(cornerRadius: 10)
                        .frame(height: 20)
                        .foregroundColor(Color.gray.opacity(0.3))
                    
                    // 2. Green Foreground Bar (Changes width based on amplitude)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: geometry.size.width * CGFloat(viewModel.currentAmplitude), height: 20)
                            .foregroundColor(.green)
                            // This animation makes it look smooth instead of jittery
                            .animation(.easeOut(duration: 0.1), value: viewModel.currentAmplitude)
                    }
                }
                .frame(height: 20) // Force the ZStack to have height
            }
            .padding(.horizontal)
            VStack(alignment: .leading) {
                HStack {
                    Text("Sensitivity Boost")
                    Spacer()
                    // Show the current number (e.g., "5.0x")
                    Text("\(String(format: "%.1f", viewModel.sensitivity))x")
                        .bold()
                }
                .font(.caption)
                .foregroundColor(.gray)
                
                // The Slider controls the 'sensitivity' variable from 1.0 to 10.0
                Slider(value: $viewModel.sensitivity, in: 1.0...20.0, step: 0.5)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Text("Real-time Pitch Detection")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(spacing: 4) {
                    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                    
                    ForEach(0..<12, id: \.self) { i in
                        VStack {
                            // The Bar
                            GeometryReader { geo in
                                VStack {
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(i == 1 || i == 3 || i == 6 || i == 8 || i == 10 ? Color.blue.opacity(0.6) : Color.blue) // Darker for black keys
                                        // Height based on chroma value
                                        .frame(height: max(geo.size.height * CGFloat(viewModel.currentChroma[i]), 0))
                                        .animation(.easeOut(duration: 0.1), value: viewModel.currentChroma[i])
                                }
                            }
                            .frame(height: 100) // Max height of bars
                            
                            // The Label
                            Text(noteNames[i])
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Button
            Button(action: {
                if !viewModel.isListening {
                    viewModel.startListening()
                } else {
                    // If stopped -> START
                    viewModel.stopListening()
                }
            }) {
                Text(viewModel.isListening ? "Stop Listening" : "Start Listening")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    // Change color: Red for Stop, Blue for Start
                    .background(viewModel.isListening ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
