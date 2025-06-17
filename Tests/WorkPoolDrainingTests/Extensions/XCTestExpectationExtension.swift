import Foundation
import XCTest

public extension XCTestExpectation {
    convenience init(checkInterval: TimeInterval = 0.05,
                     predicate: @escaping @Sendable () -> Bool,
                     dispatchQueue: DispatchQueue = .main,
                     description: String = "Periodic check expectation") {
        self.init(description: description)

        scheduleNextCheck(dispatchQueue: dispatchQueue, checkInterval: checkInterval, predicate: predicate)
    }

    convenience init(delay: TimeInterval = 0.05) {
        self.init(description: "Plain delay epxectation")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.fulfill()
        }
    }

    // MARK: Private

    private func scheduleNextCheck(dispatchQueue: DispatchQueue,
                                   checkInterval: TimeInterval,
                                   predicate: @escaping @Sendable () -> Bool) {
        dispatchQueue.asyncAfter(deadline: .now() + checkInterval) { [weak self] in
            guard let self = self else { return }
            if predicate() {
                self.fulfill()
            } else {
                self.scheduleNextCheck(dispatchQueue: dispatchQueue, checkInterval: checkInterval, predicate: predicate)
            }
        }
    }
}
