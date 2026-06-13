import SwiftUI

struct OnlineLLMSettingsView: View {
    @ObservedObject var uiModel: AutoSuggestUIModel

    @State private var onlineLLMAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SimplePanel {
                Toggle("Enable online LLM", isOn: Binding(
                    get: { uiModel.config.onlineLLM.enabled },
                    set: { uiModel.onUpdateOnlineLLMEnabled?($0) }
                ))
                Text("Use a cloud-based LLM provider for suggestions. Requires an API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if uiModel.config.onlineLLM.enabled {
                SimplePanel {
                    SectionHeader("Provider", systemImage: "cloud")

                    Picker("Provider", selection: Binding(
                        get: { uiModel.config.onlineLLM.byok.provider },
                        set: { uiModel.onUpdateOnlineLLMProvider?($0) }
                    )) {
                        ForEach(OnlineLLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    TextField("Model", text: Binding(
                        get: { uiModel.config.onlineLLM.byok.selectedModel },
                        set: { uiModel.onUpdateOnlineLLMModel?($0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    if uiModel.config.onlineLLM.byok.provider.requiresEndpointField {
                        TextField("Endpoint URL", text: Binding(
                            get: { uiModel.config.onlineLLM.byok.endpointURL ?? "" },
                            set: { uiModel.onUpdateOnlineLLMEndpoint?($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    Picker("Priority", selection: Binding(
                        get: { uiModel.config.onlineLLM.byok.priority },
                        set: { uiModel.onUpdateOnlineLLMPriority?($0) }
                    )) {
                        Text("Primary (try first)").tag(OnlineLLMPriority.primary)
                        Text("Fallback (try last)").tag(OnlineLLMPriority.fallback)
                    }
                    .pickerStyle(.segmented)
                }

                SimplePanel {
                    SectionHeader("API key", systemImage: "key")
                    SecureField("Enter API key", text: $onlineLLMAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: onlineLLMAPIKey) { newValue in
                            uiModel.onUpdateOnlineLLMAPIKey?(newValue)
                        }
                    Text("Stored securely in the system keychain. Leave blank to keep the current key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
