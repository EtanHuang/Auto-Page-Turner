import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = PageTurnerViewModel()
    
    var body: some View {
        // ScrollView is the parent container
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 25) {
                pdfSection
                statusCard
                chromaVisualizer
                controlsSection
                progressSection
                //measureList
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - UI Sections
    
    var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundStyle(viewModel.isListening ? .green : .red)
            
            Text(viewModel.statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    var pdfSection: some View {
        if let url = Bundle.main.url(forResource: "clairdelune", withExtension: "pdf") {
            ZStack {
                // 1. The bottom layer: The PDF itself
                PDFKitView(url: url, currentPage: viewModel.currentPage)
                    .frame(height: 450) // Adjust height to your liking
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .overlay(
                        HStack {
                            // Left Tap Zone
                            Color.clear
                                .frame(width: 80)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if viewModel.currentPage > 1 { viewModel.currentPage -= 1 }
                                }
                            
                            Spacer() // This allows the middle part to be "clickable/zoomable"
                            
                            // Right Tap Zone
                            Color.clear
                                .frame(width: 80)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if viewModel.currentPage < viewModel.totalPages { viewModel.currentPage += 1 }
                                }
                        }
                    )
                    .onAppear {
                        viewModel.loadPDFMetadata(url: url)
                    }
            }
        } else {
            Text("PDF not found")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
    
    var statusCard: some View {
        HStack(spacing: 40) {
            VStack {
                Text("PAGE").font(.caption).monospaced().foregroundColor(.gray)
                Text("\(viewModel.currentPage)")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
            }
            VStack {
                Text("MEASURE").font(.caption).monospaced().foregroundColor(.gray)
                Text("\(viewModel.currentMeasure)")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
            }
            VStack {
                Text("BEAT").font(.caption).monospaced().foregroundColor(.gray)
                Text("\(viewModel.currentBeat)")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
    }
    
    var chromaVisualizer: some View {
        VStack(alignment: .leading) {
            Text("Real-time Pitch Detection")
                .font(.caption).bold().foregroundColor(.gray)
            
            HStack(spacing: 4) {
                let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                ForEach(0..<12, id: \.self) { i in
                    VStack {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(i == 1 || i == 3 || i == 6 || i == 8 || i == 10 ? Color.blue.opacity(0.6) : Color.blue)
                                    .frame(height: max(geo.size.height * CGFloat(viewModel.currentChroma[i]), 0))
                                    .animation(.easeOut(duration: 0.1), value: viewModel.currentChroma[i])
                            }
                        }
                        .frame(height: 80)
                        Text(noteNames[i]).font(.system(size: 8, weight: .bold))
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        
    }
    
    var controlsSection: some View {
        VStack(spacing: 15) {
            // Sensitivity Slider
            VStack(alignment: .leading) {
                HStack {
                    Text("Sensitivity Boost").font(.caption).foregroundColor(.gray)
                    Spacer()
                    Text("\(String(format: "%.1f", viewModel.sensitivity))x").bold()
                }
                Slider(value: $viewModel.sensitivity, in: 1.0...20.0, step: 0.5)
            }
            
            // Start/Stop Button
            Button(action: {
                if viewModel.isListening { viewModel.stopListening() }
                else { viewModel.startListening() }
            }) {
                Text(viewModel.isListening ? "Stop Listening" : "Start Listening")
                    .bold().padding().frame(maxWidth: .infinity)
                    .background(viewModel.isListening ? Color.red : Color.blue)
                    .foregroundColor(.white).cornerRadius(10)
            }
        }
    }
    
    var progressSection: some View {
        VStack(alignment: .leading) {
            Text("Song Progress").font(.caption).foregroundColor(.gray)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().frame(width: geo.size.width, height: 8).opacity(0.2)
                    Rectangle()
                        .frame(width: geo.size.width * (CGFloat(viewModel.currentFrameIndex) / CGFloat(max(viewModel.referenceFeatures.count, 1))), height: 8)
                        .foregroundColor(.blue)
                        .animation(.linear, value: viewModel.currentFrameIndex)
                }
            }
            .frame(height: 8)
            Text("Frame: \(viewModel.currentFrameIndex) / \(viewModel.referenceFeatures.count)")
                .font(.system(size: 10, design: .monospaced))
        }
    }
}
