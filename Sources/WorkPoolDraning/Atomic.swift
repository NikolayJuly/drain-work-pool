import Foundation

@propertyWrapper
final class Atomic<T>: @unchecked Sendable {

    @inlinable
    var wrappedValue: T {
        get {
            lock.lock()
            defer {
                lock.unlock()
            }
            return _wrappedValue
        }
        set {
            lock.lock()
            _wrappedValue = newValue
            lock.unlock()
        }
    }

    init(wrappedValue: T) {
        self._wrappedValue = wrappedValue
    }

    /// Should be used, when checging property of wrapped value
    /// For example, adding element to array
    @discardableResult @inlinable
    func mutate<R>(_ mutation: (inout T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        let r = try mutation(&_wrappedValue)
        return r
    }

    /// Should be used, when need to check few properties on wrapped value
    @inlinable
    func read<R>(_ read: (T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        let r = try read(_wrappedValue)
        return r
    }

    // MARK: Internal

    @usableFromInline private(set) var _wrappedValue: T
    @usableFromInline let lock = PosixLock()
}

extension Atomic where T == Int {
    func increment(on value: Int = 1) {
        mutate { wrapped in
            wrapped += value
        }
    }

    func decrement(on value: Int = 1) {
        mutate { wrapped in
            wrapped -= value
        }
    }
}
