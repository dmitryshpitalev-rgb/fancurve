import Combine
import FanCurveCore
import FanCurveIPC
import Foundation
import Testing
@testable import FanCurveUI

/// A daemon whose answers the test hands out one by one.
final class ScriptedLink: DaemonLinking {
    var statusCalls = 0
    var pendingStatus: [(Result<Snapshot, Error>) -> Void] = []
    var historyRequests: [Int] = []
    var samples: [Sample] = []
    var historyFailures = 0
    var actionResult: Result<Snapshot, Error> = .success(makeSnapshot())
    var gpuResult: Result<GPUPolicyState, Error> = .success(GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))

    func status(_ done: @escaping (Result<Snapshot, Error>) -> Void) {
        statusCalls += 1
        pendingStatus.append(done)
    }

    func answerStatus(_ result: Result<Snapshot, Error>) {
        pendingStatus.removeFirst()(result)
    }

    func history(seconds: Int, _ done: @escaping (Result<[Sample], Error>) -> Void) {
        historyRequests.append(seconds)
        if historyFailures > 0 {
            historyFailures -= 1
            done(.failure(SocketError.closed))
            return
        }
        done(.success(samples))
    }

    func getConfig(_ done: @escaping (Result<Config, Error>) -> Void) { done(.success(.defaults)) }

    var sentConfigs: [Config] = []
    var pendingSetConfig: [(Result<Config, Error>) -> Void] = []

    func setConfig(_ config: Config, _ done: @escaping (Result<Config, Error>) -> Void) {
        sentConfigs.append(config)
        pendingSetConfig.append(done)
    }

    func answerSetConfig(_ result: Result<Config, Error>) {
        pendingSetConfig.removeFirst()(result)
    }

    func setEnabled(_ enabled: Bool, _ done: @escaping (Result<Snapshot, Error>) -> Void) { done(actionResult) }
    func setGPUPolicy(_ enabled: Bool, _ done: @escaping (Result<GPUPolicyState, Error>) -> Void) { done(gpuResult) }
    func retry(_ done: @escaping (Result<Snapshot, Error>) -> Void) { done(actionResult) }
}

@Suite struct AppModelTests {
    @Test func aPollPublishesTheSnapshotAndTheIcon() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        #expect(model.snapshot == makeSnapshot())
        #expect(model.connectionProblem == nil)
        #expect(model.iconModel.state == MenuBarIconState(level: 3, appearance: .normal, text: "77°"))
    }

    @Test func aFailedPollShowsTheDaemonAsUnreachable() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        #expect(model.snapshot == nil && model.connectionProblem == nil)  // connecting
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        model.poll()
        link.answerStatus(.failure(SocketError.closed))
        #expect(model.snapshot == nil)
        #expect(model.connectionProblem == UIText.connectionProblem(SocketError.closed))
        #expect(model.iconModel.state.appearance == .alert)
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        #expect(model.connectionProblem == nil)
    }

    @Test func theProblemIsPublishedOnlyWhenItChanges() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        var published: [String?] = []
        let subscription = model.$connectionProblem.sink { published.append($0) }
        for _ in 0..<3 {
            model.poll()
            link.answerStatus(.success(makeSnapshot()))
        }
        for _ in 0..<3 {
            model.poll()
            link.answerStatus(.failure(SocketError.closed))
        }
        subscription.cancel()
        // The initial value, then the problem once — not once per failed poll.
        #expect(published == [nil, UIText.connectionProblem(SocketError.closed)])
    }

    @Test func pollsDoNotPileUpBehindASlowDaemon() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        model.poll()
        model.poll()
        #expect(link.statusCalls == 1)
        link.answerStatus(.success(makeSnapshot()))
        model.poll()
        #expect(link.statusCalls == 2)
    }

    @Test func thePopupLoadsTheHourThenMergesDeltas() {
        let link = ScriptedLink()
        link.samples = PreviewData.history(seconds: 120)
        let model = AppModel(link: link)
        model.popupDidAppear()
        #expect(link.historyRequests == [AppModel.historySeconds])
        #expect(model.history.samples.count == 120)

        link.samples = PreviewData.history(endingAt: PreviewData.now + 2, seconds: 5)
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        #expect(link.historyRequests == [AppModel.historySeconds, AppModel.deltaSeconds])
        #expect(model.history.samples.count == 122)

        model.popupDidDisappear()
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        #expect(link.historyRequests.count == 2)  // a closed popup fetches no history
    }

    @Test func buttonsShowTheNewStateOrTheDaemonsRefusal() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        link.actionResult = .success(makeSnapshot(mode: .disabled))
        model.setEnabled(false)
        #expect(model.snapshot?.mode == .disabled)
        #expect(model.actionError == nil)
        #expect(!model.busy)

        link.actionResult = .failure(DaemonError.remote("safe mode: retry first"))
        model.retry()
        #expect(model.actionError == "safe mode: retry first")
        #expect(!model.busy)
    }

    @Test func theGPUPolicyToggleUpdatesThePolicyShown() {
        let link = ScriptedLink()
        let model = AppModel(link: link)
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        model.setGPUPolicy(true)
        #expect(model.snapshot?.gpuPolicy == GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
    }

    @Test func thePreviewLinkAnswersRightAway() {
        let model = AppModel(link: PreviewLink())
        model.poll()
        model.popupDidAppear()
        #expect(model.snapshot == PreviewData.snapshot)
        #expect(model.history.samples.count == 3600)
        let down = AppModel(link: UnreachableLink())
        down.poll()
        #expect(down.snapshot == nil)
    }

    /// The popup's readout shows the hour's last sample under the tiles of the status.
    @Test func thePreviewHourEndsOnTheStatus() {
        let last = PreviewData.history().last
        let status = PreviewData.snapshot
        #expect(last?.t == status.t)
        #expect(last.map { PerChannel(cpu: $0.cpu, gpu: $0.gpu, chassis: $0.chassis, power: $0.power) } == status.filtered)
        #expect(last?.fanRPM == status.fans.map(\.actualRPM))
    }

    @Test func aFailedHourIsFetchedAgainOnTheNextPoll() {
        let link = ScriptedLink()
        link.samples = PreviewData.history(seconds: 60)
        link.historyFailures = 1
        let model = AppModel(link: link)
        model.popupDidAppear()
        #expect(model.history.samples.isEmpty)
        model.poll()
        link.answerStatus(.success(makeSnapshot()))
        #expect(link.historyRequests == [AppModel.historySeconds, AppModel.historySeconds])
        #expect(model.history.samples.count == 60)
    }
}
