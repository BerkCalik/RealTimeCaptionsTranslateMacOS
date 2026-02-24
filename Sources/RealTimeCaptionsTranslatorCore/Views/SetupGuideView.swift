import SwiftUI

struct SetupGuideView: View {
    @ObservedObject var viewModel: SubtitleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            steps
            routeHelp
            footer
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.84), Color.black.opacity(0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BlackHole Setup Guide")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Install BlackHole and route system audio, then return and select it as input.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.setupSteps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.isCompleted ? .green : .white.opacity(0.7))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(step.description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var routeHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routing Tips")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("1. Open Audio MIDI Setup and verify BlackHole appears.")
            Text("2. Open Sound Input settings and choose BlackHole as input.")
            Text("3. Return to app and click Refresh, then Use BlackHole.")
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.75))
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerSingleRow
            footerTwoRows
        }
    }

    private var footerSingleRow: some View {
        HStack(spacing: 10) {
            installButton
            audioMidiButton
            soundInputButton
            Spacer(minLength: 0)
            refreshButton
            selectBlackHoleButton
            doneButton
        }
    }

    private var footerTwoRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                installButton
                audioMidiButton
                soundInputButton
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                refreshButton
                selectBlackHoleButton
                doneButton
            }
        }
    }

    private var installButton: some View {
        Button {
            viewModel.openBlackHoleDownloadPage()
        } label: {
            Text("Install BlackHole")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
    }

    private var audioMidiButton: some View {
        Button {
            viewModel.openAudioMidiSetup()
        } label: {
            Text("Audio MIDI Setup")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    private var soundInputButton: some View {
        Button {
            viewModel.openSoundInputSettings()
        } label: {
            Text("Sound Input Settings")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refreshDevicesAndSetupState()
            }
        } label: {
            Text("Refresh")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    private var selectBlackHoleButton: some View {
        Button {
            viewModel.selectFirstBlackHoleIfAvailable()
        } label: {
            Text("Select BlackHole")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.blackHoleCandidates.isEmpty)
    }

    private var doneButton: some View {
        Button {
            viewModel.closeSetupGuide()
        } label: {
            Text("Done")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
    }
}
