//
//  CheckoutView.swift
//  DrainScope Demo
//

import SwiftUI
import DrainScope
import DrainScopeUI

struct CheckoutView: View {

    @State private var model = CheckoutModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    premise
                    policyPicker
                    controls
                    resultSection
                    stepLegend
                }
                .padding(20)
            }
            .navigationTitle("Teardown under cancellation")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: Premise

    private var premise: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A checkout acquires five resources, then gets cancelled 400 ms in.")
                .font(.subheadline.weight(.semibold))
            Text(
                "Spawned as ordinary child tasks, the cleanup would inherit the cancelled "
                + "context and silently do nothing. DrainScope runs it on a shielded, budgeted "
                + "island and writes down exactly what happened."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Policy

    private var policyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drain policy")
                .font(.headline)
            Picker("Drain policy", selection: $model.preset) {
                ForEach(PolicyPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)

            Text(model.preset.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                model.start(cancelMidFlight: true)
            } label: {
                Label("Run, then cancel mid-flight", systemImage: "bolt.horizontal.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isRunning)

            HStack(spacing: 10) {
                Button("Run to completion") {
                    model.start(cancelMidFlight: false)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning)

                Button("Reset") {
                    model.reset()
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Result

    @ViewBuilder
    private var resultSection: some View {
        switch model.phase {
        case .idle:
            idlePlaceholder

        case .running:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checkout in flight…")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        case .finished(let conclusion):
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: conclusionSymbol(conclusion))
                        .foregroundStyle(conclusionTint(conclusion))
                    Text(conclusionTitle(conclusion))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                Text(conclusionBlurb(conclusion))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let transcript = model.transcript {
                    DrainTranscriptView(transcript: transcript)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func conclusionSymbol(_ conclusion: CheckoutModel.Conclusion) -> String {
        switch conclusion {
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.octagon.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func conclusionTint(_ conclusion: CheckoutModel.Conclusion) -> Color {
        switch conclusion {
        case .completed: return .green
        case .cancelled: return .red
        case .failed: return .orange
        }
    }

    private func conclusionTitle(_ conclusion: CheckoutModel.Conclusion) -> String {
        switch conclusion {
        case .completed(let value): return "Operation completed — \(value)"
        case .cancelled: return "Operation cancelled"
        case .failed: return "Operation failed"
        }
    }

    private func conclusionBlurb(_ conclusion: CheckoutModel.Conclusion) -> String {
        switch conclusion {
        case .completed:
            return "The work finished normally. Teardown runs on this path too."
        case .cancelled:
            return "The work never finished — and the teardown below still ran anyway."
        case .failed:
            return "The work threw. Teardown still ran: a failed operation needs cleanup "
                 + "just as much as a cancelled one."
        }
    }

    /// The default state says what will happen rather than showing a blank card.
    private var idlePlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No run yet")
                .font(.subheadline.weight(.semibold))
            Text("Press a button above. The transcript appears here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Legend

    private var stepLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registered steps")
                .font(.headline)
            Text("Teardown runs bottom-to-top — reverse registration order.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(DemoScenario.steps) { step in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(step.name)
                            .font(.subheadline.weight(.medium))
                        Text(step.criticality.rawValue)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (step.criticality == .required ? Color.orange : Color.secondary)
                                    .opacity(0.18),
                                in: Capsule()
                            )
                        Spacer(minLength: 4)
                        if step.throwsAfterWork {
                            Text("throws")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        Text("\(step.work.drainMilliseconds) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(step.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    CheckoutView()
}
