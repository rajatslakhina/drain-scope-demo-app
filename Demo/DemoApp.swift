//
//  DemoApp.swift
//  DrainScope Demo
//
//  The app owns the scenario and the policy presets — the compiled-in
//  configuration that DrainScopeUI's view renders. The library supplies the
//  teardown machinery and the transcript type; it has no opinion about what a
//  checkout is.
//

import SwiftUI
import Observation
import DrainScope

// MARK: - Scenario

/// One simulated resource acquired during checkout, and the teardown it needs.
///
/// `Sendable` because the teardown closure built from it crosses into the
/// drain's shielded execution context.
struct DemoStep: Sendable, Identifiable {
    let name: String
    let criticality: DrainCriticality
    /// How long this step's teardown takes. The whole demo turns on the
    /// relationship between these numbers and the policy's budget.
    let work: Duration
    /// When true the teardown throws after doing its work.
    ///
    /// Present because a budget cannot fix a step that is simply broken, and the
    /// transcript has to distinguish "ran out of time" from "raised". Without a
    /// step that throws, `DrainOutcome.failed` is unreachable in this app and the
    /// red row in `DrainTranscriptView` is never rendered.
    let throwsAfterWork: Bool
    let blurb: String

    var id: String { name }
}

/// The error a deliberately-broken teardown step raises.
enum DemoTeardownError: Error, CustomStringConvertible {
    case endpointGone(String)

    var description: String {
        switch self {
        case .endpointGone(let name): return "\(name): endpoint returned 410 Gone"
        }
    }
}

enum DemoScenario {

    /// Registered in this order, so teardown runs bottom-to-top (LIFO).
    static let steps: [DemoStep] = [
        DemoStep(
            name: "reserve-inventory",
            criticality: .bestEffort,
            work: .milliseconds(120),
            throwsAfterWork: false,
            blurb: "Release the stock hold. The warehouse reaps stale holds anyway."
        ),
        DemoStep(
            name: "release-payment-hold",
            criticality: .required,
            work: .milliseconds(80),
            throwsAfterWork: false,
            blurb: "Release the authorization. Skipping it parks real money."
        ),
        DemoStep(
            name: "rollback-transaction",
            criticality: .required,
            work: .milliseconds(60),
            throwsAfterWork: false,
            blurb: "Roll back the open transaction. Skipping it corrupts the order."
        ),
        DemoStep(
            name: "flush-analytics",
            criticality: .bestEffort,
            work: .milliseconds(400),
            throwsAfterWork: false,
            blurb: "Upload funnel events. Slow, and nobody should wait on it."
        ),
        DemoStep(
            name: "sync-wishlist",
            criticality: .bestEffort,
            work: .milliseconds(20),
            throwsAfterWork: true,
            blurb: "Always throws. A failing step is recorded and the drain continues."
        )
    ]

    /// How long the "real work" runs before it can be cancelled.
    static let workDuration: Duration = .seconds(5)

    /// When the cancel button fires relative to the start of the work.
    static let cancelDelay: Duration = .milliseconds(400)
}

// MARK: - Policy presets

enum PolicyPreset: String, CaseIterable, Identifiable {
    case tight = "Tight"
    case standard = "Default"
    case hostile = "Hostile"
    case patient = "Patient"
    case doomed = "Doomed"

    var id: String { rawValue }

    var policy: DrainPolicy {
        switch self {
        case .tight:
            // Not a library preset — defined here because it is the one that
            // produces four of the five outcome kinds in a single transcript,
            // which is the point of a demo.
            return DrainPolicy(
                totalBudget: .milliseconds(250),
                requiredStepGrace: .milliseconds(200),
                capacity: 32
            )
        case .standard: return .default
        case .hostile: return .hostile
        case .patient: return .patient
        case .doomed:
            // No budget and no grace: nothing can be granted any time at all.
            // Exists so `DrainOutcome.notAttempted` is reachable in the demo —
            // the library's "the transcript never claims a step ran when it
            // did not" guarantee is otherwise impossible to see.
            return DrainPolicy(totalBudget: .zero, requiredStepGrace: .zero, capacity: 32)
        }
    }

    var explanation: String {
        switch self {
        case .tight:
            return "250 ms total, 200 ms grace. Wishlist throws, analytics overruns its cap, the "
                 + "budget is then gone so inventory is dropped — and both required steps still "
                 + "get their grace. Four of the five outcome kinds in one transcript; pick "
                 + "Doomed for the fifth."
        case .standard:
            return "2 s total, 250 ms grace. Everything is reached and given all the time it "
                 + "needs. The wishlist sync still fails: a budget cannot fix a broken step."
        case .hostile:
            return "No budget at all, 100 ms grace. Every best-effort step is dropped on sight; "
                 + "only required work runs. This is the termination posture."
        case .patient:
            return "30 s total, 5 s grace. For batch and CLI contexts, where finishing beats exiting."
        case .doomed:
            return "No budget and no grace. Nothing is granted any time, so the required steps "
                 + "read notAttempted rather than timedOut — they never started, and the "
                 + "transcript says so instead of claiming they were cancelled."
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class CheckoutModel {

    enum Phase: Equatable {
        case idle
        case running
        case finished(Conclusion)
    }

    /// Mirrors `OperationOutcome`'s three cases rather than collapsing them into
    /// a bool. Collapsing would render a failed checkout with a green seal and
    /// the words "the work finished normally" — and keeping "did the work
    /// succeed" separate from "did cleanup run" is the reason
    /// `OperationOutcome` exists in the first place.
    enum Conclusion: Equatable {
        case completed(String)
        case cancelled
        case failed
    }

    var preset: PolicyPreset = .tight
    private(set) var phase: Phase = .idle
    private(set) var transcript: DrainTranscript?

    private var workTask: Task<Void, Never>?

    var isRunning: Bool { phase == .running }

    /// Runs the checkout. When `cancelMidFlight` is true it is cancelled
    /// `DemoScenario.cancelDelay` in — the case the library exists for.
    func start(cancelMidFlight: Bool) {
        guard !isRunning else { return }

        phase = .running
        transcript = nil

        let policy = preset.policy
        let steps = DemoScenario.steps

        let task = Task { @MainActor [weak self] in
            let run: DrainRun<String> = await withDrainScope(policy: policy) { scope in
                for step in steps {
                    try await scope.register(step.name, criticality: step.criticality) {
                        try await Task.sleep(for: step.work)
                        if step.throwsAfterWork {
                            throw DemoTeardownError.endpointGone(step.name)
                        }
                    }
                }
                try await Task.sleep(for: DemoScenario.workDuration)
                return "order-placed"
            }
            self?.finish(with: run)
        }
        workTask = task

        guard cancelMidFlight else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: DemoScenario.cancelDelay)
            self?.workTask?.cancel()
        }
    }

    func reset() {
        workTask?.cancel()
        workTask = nil
        phase = .idle
        transcript = nil
    }

    private func finish(with run: DrainRun<String>) {
        transcript = run.transcript
        switch run.outcome {
        case .completed(let value): phase = .finished(.completed(value))
        case .cancelled: phase = .finished(.cancelled)
        case .failed: phase = .finished(.failed)
        }
        workTask = nil
    }
}

// MARK: - Entry point

@main
struct DrainScopeDemoApp: App {
    var body: some Scene {
        WindowGroup {
            CheckoutView()
        }
    }
}
