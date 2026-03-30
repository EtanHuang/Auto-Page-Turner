import Foundation

struct Score: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let composer: String
    let pdfFileName: String
    let jsonFileName: String
    let pageBreaks: [Int]
    // Optional: add a cover image string if you want thumbnails later
}
