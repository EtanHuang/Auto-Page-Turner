import SwiftUI

struct ContentView: View {
    // 1. Your library of songs lives here, at the top level!
    @State private var myScores: [Score] = [
        Score(title: "Waterfall Etude", composer: "F. Chopin", pdfFileName: "waterfall", jsonFileName: "waterfall_features_full", pageBreaks: [1, 10, 20, 28, 38, 46, 56, 66, 74]),
        Score(title: "La Campanella", composer: "F. Liszt", pdfFileName: "lacampanella", jsonFileName: "lacampanella_features_full", pageBreaks: [1, 14, 26, 40]),
        Score(title: "Ballade No. 1", composer: "F. Chopin", pdfFileName: "ballade1", jsonFileName: "ballade1_features_full", pageBreaks: [1, 21, 41, 55, 73, 90, 109, 125, 140, 155, 172, 205, 224, 244]),
        Score(title: "Clair De Lune", composer: "C. Debussy", pdfFileName: "clairdelune", jsonFileName: "clairdelune_features_full", pageBreaks: [1,14,28,38,48,58])
    ]
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
            NavigationView {
                // 3. Changed to a Vertical ScrollView
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading) {
                        Text("My Library")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                            .padding(.top, 20)
                        
                        // 4. Swapped HStack for LazyVGrid
                        LazyVGrid(columns: columns, spacing: 30) {
                            
                            // The List of Scores
                            ForEach(myScores) { score in
                                NavigationLink(destination: PageTurnerView(score: score)) {
                                    ScoreCardView(score: score)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // The "Add Score" Button
                            Button(action: {
                                print("Tapped Add Score - open document picker here")
                            }) {
                                VStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                    Text("Add Score")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                // Matching the exact frame size of ScoreCardView
                                .frame(width: 160, height: 220)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(15)
                                .shadow(radius: 5)
                            }
                        }
                        .padding()
                    }
                }
                .navigationBarHidden(true)
            }
            .navigationViewStyle(.stack)
        }
    }


// A reusable subview for the individual score cards
struct ScoreCardView: View {
    let score: Score
    
    var body: some View {
        VStack(alignment: .leading) {
            // Placeholder for a cover image
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 140)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(score.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(score.composer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding([.horizontal, .bottom], 12)
            .padding(.top, 8)
        }
        .frame(width: 160, height: 220)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
    }
}
