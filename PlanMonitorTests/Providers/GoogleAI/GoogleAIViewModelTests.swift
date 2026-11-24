import Foundation
import Testing
@testable import PlanMonitor

/// The provider's states, driven by a fake runner: nothing on the machine is ever run.
@Suite("Google AI view model")
@MainActor
struct GoogleAIViewModelTests {

    @Test func noScriptMeansSetupAndNothingRuns() async {
        await withDefaultsAsync { defaults in
            let runner = FakeGoogleAIRunner(state: .notInstalled)
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: runner)
            await viewModel.resume()
            #expect(await waitUntil { viewModel.lastError == .scriptMissing })
            #expect(viewModel.needsSetup)
            #expect(!viewModel.showsUsage)
            #expect(runner.runs == 0)
            await viewModel.suspend()
        }
    }

    @Test func aGoodRunShowsTheFiguresAndPersistsThem() async {
        await withDefaultsAsync { defaults in
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: FakeGoogleAIRunner())
            await viewModel.resume()
            #expect(await waitUntil { !viewModel.usage.isEmpty })
            #expect(viewModel.showsUsage)
            #expect(!viewModel.needsSetup)
            #expect(viewModel.usage.buckets.count == 5)
            #expect(GoogleAISnapshotStore(defaults: defaults).load()?.usage == viewModel.usage)
            await viewModel.suspend()
        }
    }

    @Test func agyMissingIsASetupStateNotAnError() async {
        await withDefaultsAsync { defaults in
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: FakeGoogleAIRunner(result: .failure(.agyNotFound)))
            await viewModel.resume()
            #expect(await waitUntil { viewModel.lastError == .agyNotFound })
            #expect(viewModel.needsSetup)
            #expect(viewModel.errorMessage == nil)
            await viewModel.suspend()
        }
    }

    @Test func aTransientFailureKeepsTheFiguresWithALine() async {
        await withDefaultsAsync { defaults in
            let runner = FakeGoogleAIRunner()
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: runner)
            await viewModel.resume()
            #expect(await waitUntil { !viewModel.usage.isEmpty })

            runner.set(result: .failure(.agyFailed(exit: 1)))
            await viewModel.refreshUsage()
            #expect(await waitUntil { viewModel.lastError == .agyFailed(exit: 1) })
            #expect(viewModel.usage.buckets.count == 5)
            #expect(viewModel.showsUsage)
            #expect(viewModel.errorMessage != nil)
            await viewModel.suspend()
        }
    }

    @Test func aChangedReportKeepsTheLastFigures() async {
        await withDefaultsAsync { defaults in
            let runner = FakeGoogleAIRunner()
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: runner)
            await viewModel.resume()
            #expect(await waitUntil { !viewModel.usage.isEmpty })

            runner.set(result: .success(Data("{}".utf8)))
            await viewModel.refreshUsage()
            #expect(await waitUntil { viewModel.lastError == .reportChanged })
            #expect(viewModel.usage.buckets.count == 5)
            await viewModel.suspend()
        }
    }

    @Test func aRelaunchShowsThePersistedFiguresAtOnce() async {
        await withDefaultsAsync { defaults in
            let usage = try! GoogleAIUsageReport.parse(GoogleAIFixtures.report)
            GoogleAISnapshotStore(defaults: defaults).save(usage: usage, lastUpdated: Date())
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: FakeGoogleAIRunner(result: .failure(.timedOut)))
            await viewModel.resume()
            #expect(viewModel.usage == usage)
            await viewModel.suspend()
        }
    }

    @Test func demoShowsFiguresAndPersistsNothing() async {
        await withDefaultsAsync { defaults in
            let runner = FakeGoogleAIRunner(state: .notInstalled)
            let viewModel = GoogleAIViewModel(defaults: defaults, runner: runner)
            viewModel.enterDemo()
            #expect(viewModel.showsUsage)
            #expect(!viewModel.needsSetup)
            #expect(viewModel.usage.geminiFiveHour != nil)
            #expect(GoogleAISnapshotStore(defaults: defaults).load() == nil)
            #expect(runner.runs == 0)
        }
    }
}
