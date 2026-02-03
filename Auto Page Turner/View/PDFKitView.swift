import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let currentPage: Int
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true // Fits the page to the screen width
        pdfView.displayMode = .singlePage
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document else { return }
        if let page = document.page(at: currentPage - 1) {
            uiView.go(to: page)
        }
    }
    
}
