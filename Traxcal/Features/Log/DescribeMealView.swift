import SwiftUI

/// "I had two eggs, toast and a latte" → AI estimate → editable review → log.
struct DescribeMealView: View {
    var onDone: () -> Void

    @Environment(AIRouter.self) private var ai
    @State private var text = ""
    @State private var analysis: FoodAnalysis?
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe what you ate").font(.display(24, weight: .bold))
                Text("Include amounts and brands when you can. Your AI: \(ai.backend.title)")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. 2 scrambled eggs, a slice of sourdough with butter and a grande oat latte", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .focused($focused)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                PrimaryButton(title: isWorking ? "Estimating…" : "Estimate Nutrition", symbol: "sparkles", color: Palette.fat) {
                    Task { await run() }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)

                if isWorking { ForEach(0..<3, id: \.self) { _ in ShimmerView().frame(height: 60) } }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning).font(.subheadline)
                }
            }
            .padding(16)
        }
        .navigationTitle("Describe")
        .onAppear { focused = true }
        .navigationDestination(item: $analysis) { result in
            AnalysisReviewView(analysis: result, photo: nil, onDone: onDone)
        }
    }

    private func run() async {
        focused = false
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            analysis = try await ai.analyzeText(text)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}

extension FoodAnalysis: Hashable, Identifiable {
    var id: String { items.map(\.id.uuidString).joined() }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
