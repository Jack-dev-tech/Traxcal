import PhotosUI
import SwiftUI

/// Take or pick a meal photo, let the selected AI analyze it, then review & log.
struct ScanMealView: View {
    var onDone: () -> Void

    @Environment(AIRouter.self) private var ai
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var hint = ""
    @State private var analysis: FoodAnalysis?
    @State private var isWorking = false
    @State private var error: String?
    @State private var scanLine: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }

                TextField("Optional hint: \"large portion\", \"cooked in olive oil\"…", text: $hint, axis: .vertical)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                PrimaryButton(title: isWorking ? "Analyzing…" : "Analyze with AI", symbol: "sparkles", color: Palette.fat) {
                    Task { await analyze() }
                }
                .disabled(image == nil || isWorking)
                .opacity(image == nil ? 0.5 : 1)

                Label("Using \(ai.backend.title)", systemImage: "cpu").font(.caption).foregroundStyle(.secondary)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.warning)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
        }
        .navigationTitle("Scan Meal")
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $image).ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    withAnimation(Theme.spring) { image = ui }
                }
            }
        }
        .onChange(of: image) { _, new in
            if new != nil { Haptics.tap(); error = nil }
        }
        .navigationDestination(item: $analysis) { result in
            AnalysisReviewView(analysis: result, photo: image, onDone: onDone)
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner).fill(.white.opacity(0.05))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 320)
                    .clipShape(.rect(cornerRadius: Theme.corner))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 54)).foregroundStyle(Palette.fat)
                        .symbolEffect(.breathe)
                    Text("Snap your plate").font(.headline)
                    Text("AI identifies each food and estimates portions.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if isWorking {
                // Animated scan line sweeping over the photo.
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Palette.fat.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .offset(y: scanLine * (geo.size.height - 70))
                        .blendMode(.screen)
                }
                .clipShape(.rect(cornerRadius: Theme.corner))
                .onAppear {
                    scanLine = 0
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { scanLine = 1 }
                }
            }
        }
        .frame(height: 320)
    }

    private func analyze() async {
        guard let image else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            analysis = try await ai.analyzePhoto(image, hint: hint)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
