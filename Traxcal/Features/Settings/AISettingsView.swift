import SwiftUI

struct AISettingsView: View {
    @Environment(AIRouter.self) private var ai
    @Environment(LocalModelManager.self) private var models
    @State private var testResult: String?
    @State private var testing = false

    private let device = DeviceCapability.current

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Active: \(ai.backend.title)", systemImage: "sparkles").font(.headline)
                    if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                }
                Button {
                    testing = true
                    Task {
                        let result = await ai.test()
                        switch result {
                        case .success(let s): testResult = "✓ \(s)"; Haptics.success()
                        case .failure(let e): testResult = "✗ \(e.localizedDescription)"; Haptics.error()
                        }
                        testing = false
                    }
                } label: {
                    HStack { Text("Test connection"); if testing { Spacer(); ProgressView() } }
                }
                .disabled(ai.backend == .none || testing)
                Button("Turn AI off", role: .destructive) { ai.backend = .none }
                    .disabled(ai.backend == .none)
            }

            Section {
                let status = AppleIntelligenceProvider.availability
                Button {
                    ai.backend = .appleIntelligence
                    Haptics.selection()
                } label: {
                    selectableRow("Apple Intelligence", status.reason ?? "Built-in, private and free. Photos use on-device image recognition.",
                                  symbol: "apple.intelligence", selected: ai.backend == .appleIntelligence)
                }
                .disabled(!status.available)
            } header: {
                Text("Built-in")
            }

            Section {
                ForEach(LocalModelCatalog.all) { model in
                    LocalModelRow(model: model, recommended: model.id == LocalModelCatalog.recommended(for: device).id, device: device)
                }
            } header: {
                Text("On-Device Models")
            } footer: {
                Text("Your iPhone (\(device.modelIdentifier), \(device.marketingRAM) RAM) is in the \(device.tier.title) tier. Models run fully offline with MLX; nothing leaves your phone. Larger models are more accurate but slower and use more storage.")
            }

            Section {
                ForEach(CloudProvider.allCases) { provider in
                    NavigationLink {
                        CloudProviderView(provider: provider)
                    } label: {
                        selectableRow(
                            provider.title,
                            ai.apiKey(for: provider).isEmpty && provider.requiresKey ? "No key" : (ai.cloudConfigs[provider]?.model ?? ""),
                            symbol: provider.symbol, selected: ai.backend == .cloud(provider)
                        )
                    }
                }
            } header: {
                Text("Cloud Providers (Bring Your Own Key)")
            } footer: {
                Text("Keys are stored in the iOS Keychain on this device. Photos and food descriptions are sent to the provider you choose.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("AI Assistant")
        .sensoryFeedback(.selection, trigger: ai.backend)
    }

    private func selectableRow(_ title: String, _ subtitle: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: UIImage(systemName: symbol) == nil ? "cpu" : symbol)
                .frame(width: 28)
                .foregroundStyle(Palette.fat)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.protein).transition(.scale)
            }
        }
        .animation(Theme.bouncy, value: selected)
    }
}

private struct LocalModelRow: View {
    var model: LocalModel
    var recommended: Bool
    var device: DeviceCapability

    @Environment(AIRouter.self) private var ai
    @Environment(LocalModelManager.self) private var manager
    @State private var confirmDelete = false

    var body: some View {
        let state = manager.state(model)
        let fits = model.runs(on: device.tier)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.headline)
                        if recommended {
                            Text("RECOMMENDED").font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.protein, in: .capsule).foregroundStyle(.black)
                        }
                    }
                    HStack(spacing: 8) {
                        Label(model.vision ? "Vision + text" : "Text only", systemImage: model.vision ? "eye" : "text.alignleft")
                        Text("\(model.parameters) · \(model.downloadGB.formatted(.number.precision(.fractionLength(1)))) GB")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Text(model.blurb).font(.caption).foregroundStyle(.secondary)
                    if !fits {
                        Label("May not run well on this iPhone", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(Palette.carbs)
                    }
                }
                Spacer()
                if ai.backend == .onDevice(modelID: model.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.protein)
                }
            }
            switch state {
            case .notDownloaded, .failed:
                if case .failed(let msg) = state { Text(msg).font(.caption2).foregroundStyle(Palette.warning) }
                Button {
                    manager.download(model)
                    Haptics.press()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.glass)
            case .downloading(let progress):
                HStack {
                    ProgressView(value: progress).tint(Palette.fat)
                    Text("\(Int(progress * 100))%").font(.caption.monospacedDigit())
                    Button("Cancel") { manager.cancel(model) }.font(.caption)
                }
            case .downloaded:
                HStack {
                    Button {
                        ai.backend = .onDevice(modelID: model.id)
                        Haptics.success()
                    } label: {
                        Label(ai.backend == .onDevice(modelID: model.id) ? "In use" : "Use this model", systemImage: "cpu")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(ai.backend == .onDevice(modelID: model.id))
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }.font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
        .confirmationDialog("Delete \(model.name)?", isPresented: $confirmDelete) {
            Button("Delete \(ByteCountFormatter.string(fromByteCount: manager.diskUsage(model), countStyle: .file))", role: .destructive) {
                if ai.backend == .onDevice(modelID: model.id) { ai.backend = .none }
                manager.delete(model)
            }
        }
    }
}

private struct CloudProviderView: View {
    var provider: CloudProvider
    @Environment(AIRouter.self) private var ai
    @State private var key = ""
    @State private var config = CloudProviderConfig(model: "", baseURL: "", supportsVision: true)
    @State private var reveal = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if reveal { TextField("API key", text: $key) } else { SecureField("API key", text: $key) }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                if let url = provider.keyURL { Link("Get a \(provider.title) key", destination: url) }
            } header: {
                Text(provider.requiresKey ? "API Key" : "API Key (optional)")
            }

            Section {
                TextField("Model", text: $config.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Base URL", text: $config.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Toggle("Model accepts images", isOn: $config.supportsVision)
                Button("Reset to defaults") {
                    config = CloudProviderConfig(model: provider.defaultModel, baseURL: provider.baseURL, supportsVision: provider.defaultSupportsVision)
                }
            } header: {
                Text("Model")
            } footer: {
                Text(provider == .custom
                     ? "Any OpenAI-compatible server works, e.g. Ollama or LM Studio on your Mac (use its LAN address)."
                     : "Change the model name any time the provider releases a newer one. Text-only models scan photos using on-device image recognition.")
            }

            Section {
                PrimaryButton(title: ai.backend == .cloud(provider) ? "Save" : "Save & Use \(provider.title)", symbol: "checkmark", color: Palette.fat) {
                    ai.setAPIKey(key, for: provider)
                    ai.cloudConfigs[provider] = config
                    ai.backend = .cloud(provider)
                    Haptics.success()
                }
                .disabled(provider.requiresKey && key.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(provider.title)
        .onAppear {
            key = ai.apiKey(for: provider)
            config = ai.cloudConfigs[provider] ?? config
        }
    }
}
