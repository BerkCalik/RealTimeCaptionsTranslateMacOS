import SwiftUI

enum UITheme {
    case cinematicTealAmber
}

struct UIStyleTokens {
    let backgroundTop: Color
    let backgroundBottom: Color
    let vignette: Color
    let surface: Color
    let surfaceStrong: Color
    let border: Color
    let divider: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let highlight: Color
    let danger: Color

    init(theme: UITheme) {
        switch theme {
        case .cinematicTealAmber:
            backgroundTop = Color(red: 0.04, green: 0.14, blue: 0.16)
            backgroundBottom = Color(red: 0.03, green: 0.06, blue: 0.09)
            vignette = Color.black.opacity(0.45)
            surface = Color.black.opacity(0.42)
            surfaceStrong = Color.black.opacity(0.58)
            border = Color.white.opacity(0.16)
            divider = Color.white.opacity(0.10)
            textPrimary = Color.white.opacity(0.96)
            textSecondary = Color.white.opacity(0.75)
            accent = Color(red: 0.98, green: 0.74, blue: 0.34)
            highlight = Color(red: 0.29, green: 0.75, blue: 0.78)
            danger = Color(red: 0.95, green: 0.38, blue: 0.36)
        }
    }
}

enum ControlLayoutMode {
    case compact
    case balanced
    case stacked
}

struct SubtitleView: View {
    @ObservedObject var viewModel: SubtitleViewModel

    private let tokens = UIStyleTokens(theme: .cinematicTealAmber)

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = controlLayoutMode(for: geometry.size.width)
            let subtitleMinHeight = subtitlePanelMinHeight(
                forTotalHeight: geometry.size.height,
                mode: layoutMode
            )

            ZStack {
                backgroundLayer

                VStack(spacing: 14) {
                    englishContainer(minHeight: subtitleMinHeight)
                    translationContainer(minHeight: subtitleMinHeight)
                    setupBanner
                    controls(mode: layoutMode)
                    statusStrip
                }
                .padding(18)
            }
            .animation(.easeInOut(duration: 0.16), value: layoutMode)
        }
        .frame(minWidth: 980, minHeight: 720)
        .task {
            await viewModel.refreshDevicesAndSetupState()
        }
        .alert(viewModel.alertTitle, isPresented: isErrorAlertPresented) {
            Button("OK", role: .cancel) {
                viewModel.dismissErrorAlert()
            }
        } message: {
            Text(viewModel.errorAlertMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "BlackHole was not detected.",
            isPresented: $viewModel.isBlackHoleContinueDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Continue Anyway") {
                viewModel.continueStartWithoutBlackHole()
            }
            Button("Open Setup") {
                viewModel.openSetupFromStartWarning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Continue with the current input device, or open setup guidance.")
        }
        .sheet(isPresented: $viewModel.isSetupGuidePresented) {
            SetupGuideView(viewModel: viewModel)
        }
    }

    private var isErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorAlertMessage != nil },
            set: { newValue in
                if newValue == false {
                    viewModel.dismissErrorAlert()
                }
            }
        )
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [tokens.backgroundTop, tokens.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [tokens.highlight.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 460
            )
            .blendMode(.plusLighter)

            RadialGradient(
                colors: [tokens.accent.opacity(0.13), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 540
            )
            .blendMode(.plusLighter)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.03), .clear, Color.white.opacity(0.015)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.softLight)

            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, tokens.vignette],
                        center: .center,
                        startRadius: 80,
                        endRadius: 900
                    )
                )
        }
        .ignoresSafeArea()
    }

    private func englishContainer(minHeight: CGFloat) -> some View {
        subtitlePanel(
            title: "English",
            lines: viewModel.subtitleLines,
            emptyText: "Start listening to show live subtitles.",
            minHeight: minHeight,
            onCopy: viewModel.copyEnglishText
        )
    }

    private func translationContainer(minHeight: CGFloat) -> some View {
        subtitlePanel(
            title: "Turkish Translation",
            lines: viewModel.translatedLines,
            emptyText: "Translation appears here.",
            minHeight: minHeight,
            onCopy: viewModel.copyTurkishText
        )
    }

    private func subtitlePanel(
        title: String,
        lines: [String],
        emptyText: String,
        minHeight: CGFloat,
        onCopy: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(tokens.textSecondary)

                Spacer(minLength: 0)

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tokens.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tokens.surface)
                )
                .overlay(
                    Circle()
                        .stroke(tokens.border, lineWidth: 1)
                )
                .help("Copy \(title) text")
                .disabled(lines.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if lines.isEmpty {
                            Text(emptyText)
                                .font(.system(size: max(16, viewModel.fontSize * 0.38), weight: .medium, design: .rounded))
                                .foregroundStyle(tokens.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: viewModel.fontSize, weight: .semibold, design: .rounded))
                                    .foregroundStyle(tokens.textPrimary)
                                    .lineSpacing(max(2, viewModel.fontSize * 0.12))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: lines.count) { _, newCount in
                    guard newCount > 0 else { return }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(tokens.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tokens.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 12, y: 8)
    }

    @ViewBuilder
    private func controls(mode: ControlLayoutMode) -> some View {
        switch mode {
        case .compact:
            HStack(alignment: .top, spacing: 10) {
                inputModelSection
                actionLatencySection
                preferencesSection
            }
            .padding(12)
            .panelSurface(tokens: tokens)

        case .balanced:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    inputModelSection
                    actionLatencySection
                }
                preferencesSection
            }
            .padding(12)
            .panelSurface(tokens: tokens)

        case .stacked:
            VStack(alignment: .leading, spacing: 10) {
                inputModelSection
                actionLatencySection
                preferencesSection
            }
            .padding(12)
            .panelSurface(tokens: tokens)
        }
    }

    @ViewBuilder
    private var setupBanner: some View {
        switch viewModel.audioSetupState {
        case .blackHoleMissing:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(tokens.accent)
                Text("BlackHole not detected. Install and route system audio for best results.")
                    .font(.callout)
                    .foregroundStyle(tokens.textPrimary)
                Spacer(minLength: 8)
                Button("Open Setup") {
                    viewModel.openSetupGuide()
                }
                .buttonStyle(.borderedProminent)
                .tint(tokens.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .panelSurface(tokens: tokens)

        case .blackHoleAvailableNotSelected:
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(tokens.highlight)
                Text("BlackHole detected. Select it as Input Device for system-audio capture.")
                    .font(.callout)
                    .foregroundStyle(tokens.textPrimary)
                Spacer(minLength: 8)
                Button("Use BlackHole") {
                    viewModel.selectFirstBlackHoleIfAvailable()
                }
                .buttonStyle(.bordered)
                Button("Setup") {
                    viewModel.openSetupGuide()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .panelSurface(tokens: tokens)

        case .blackHoleSelected:
            HStack(spacing: 8) {
                Circle()
                    .fill(tokens.highlight)
                    .frame(width: 8, height: 8)
                Text("BlackHole ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tokens.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panelSurface(tokens: tokens)

        case .ready:
            EmptyView()
        }
    }

    private var inputModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Input & Model")

            HStack(spacing: 8) {
                Picker("Input Device", selection: $viewModel.selectedDeviceID) {
                    ForEach(viewModel.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 210, maxWidth: .infinity)

                Picker("Model", selection: $viewModel.selectedTranslationModel) {
                    ForEach(TranslationModelOption.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .labelsHidden()
                .frame(width: 165)
                .onChange(of: viewModel.selectedTranslationModel) { _, _ in
                    viewModel.applySelectedTranslationModel()
                }

                Button("Refresh") {
                    Task {
                        await viewModel.refreshDevicesAndSetupState()
                    }
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 88)

                Button("Setup") {
                    viewModel.openSetupGuide()
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 80)
            }
        }
        .toolbarSection(tokens: tokens)
    }

    private var actionLatencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Actions & Latency")

            HStack(spacing: 8) {
                Button("Start") {
                    viewModel.start()
                }
                .disabled(viewModel.isListening || viewModel.selectedDeviceID.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(tokens.accent)
                .frame(minWidth: 84)

                Button("Stop") {
                    viewModel.stop()
                }
                .disabled(!viewModel.isListening)
                .buttonStyle(.bordered)
                .frame(minWidth: 84)

                Button("Clear") {
                    viewModel.clearSubtitles()
                }
                .disabled(viewModel.subtitleLines.isEmpty && viewModel.translatedLines.isEmpty)
                .buttonStyle(.bordered)
                .frame(minWidth: 84)
            }

            Picker("Latency", selection: $viewModel.selectedLatencyPreset) {
                ForEach(TranslationLatencyPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedLatencyPreset) { _, _ in
                viewModel.applyLatencyPreset()
            }
        }
        .toolbarSection(tokens: tokens)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Preferences")

            Toggle("Keep tech words original", isOn: $viewModel.keepTechWordsOriginal)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(tokens.textPrimary)
                .onChange(of: viewModel.keepTechWordsOriginal) { _, _ in
                    viewModel.applyKeepTechWordsPreference()
                }

            HStack(spacing: 10) {
                SecureField("OpenAI API token", text: $viewModel.apiToken)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.applyAPIToken()
                    }

                Button("Save Token") {
                    viewModel.applyAPIToken()
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 98)
            }

            HStack(spacing: 10) {
                Text("Font Size")
                    .font(.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .frame(width: 58, alignment: .leading)

                Slider(value: $viewModel.fontSize, in: 12 ... 72, step: 1)
                    .frame(minWidth: 140, maxWidth: .infinity)

                Text("\(Int(viewModel.fontSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tokens.textSecondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .toolbarSection(tokens: tokens)
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 4)

            Text(stateLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.textPrimary)

            Rectangle()
                .fill(tokens.divider)
                .frame(width: 1, height: 12)

            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(tokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tokens.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tokens.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 6)
        .transition(.opacity)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tokens.textSecondary)
    }

    private func controlLayoutMode(for width: CGFloat) -> ControlLayoutMode {
        if width >= 1420 {
            return .compact
        }
        if width >= 1080 {
            return .balanced
        }
        return .stacked
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .idle:
            return tokens.textSecondary
        case .listening:
            return tokens.accent
        case .error:
            return tokens.danger
        }
    }

    private func subtitlePanelMinHeight(
        forTotalHeight totalHeight: CGFloat,
        mode: ControlLayoutMode
    ) -> CGFloat {
        let controlsEstimate: CGFloat
        switch mode {
        case .compact:
            controlsEstimate = 190
        case .balanced:
            controlsEstimate = 250
        case .stacked:
            controlsEstimate = 320
        }

        let outerPadding: CGFloat = 36
        let stackSpacing: CGFloat = 42
        let statusStripEstimate: CGFloat = 42
        let remaining = totalHeight - outerPadding - stackSpacing - controlsEstimate - statusStripEstimate
        let half = max(130, remaining / 2)
        let fontDriven = max(130, viewModel.fontSize * 3.2)
        return min(fontDriven, half)
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .error:
            return "Error"
        }
    }
}

private struct ToolbarSectionModifier: ViewModifier {
    let tokens: UIStyleTokens

    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tokens.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tokens.border, lineWidth: 1)
            )
    }
}

private extension View {
    func toolbarSection(tokens: UIStyleTokens) -> some View {
        modifier(ToolbarSectionModifier(tokens: tokens))
    }

    func panelSurface(tokens: UIStyleTokens) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(tokens.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tokens.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 12, y: 8)
    }
}
