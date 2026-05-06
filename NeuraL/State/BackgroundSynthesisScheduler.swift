import BackgroundTasks
import Foundation

final class BackgroundSynthesisScheduler {
    static let shared = BackgroundSynthesisScheduler()
    static let refreshIdentifier = "com.neural.shadow-memory.refresh"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { task in
            self.handle(task: task)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(task: BGTask) {
        schedule()

        let operation = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
