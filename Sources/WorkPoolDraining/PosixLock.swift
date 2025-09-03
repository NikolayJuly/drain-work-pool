import Foundation

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#elseif os(Windows)
import ucrt
import WinSDK
#else
import Glibc
#endif

// I took this implementation from NIO implementation: https://github.com/apple/swift-nio/blob/main/Sources/NIOConcurrencyHelpers/NIOLock.swift

#if os(Windows)
@usableFromInline
typealias LockPrimitive = SRWLOCK
#else
@usableFromInline
typealias LockPrimitive = pthread_mutex_t
#endif

@usableFromInline
enum LockOperations {}

extension LockOperations {
    @inlinable
    static func create(_ mutex: UnsafeMutablePointer<LockPrimitive>) {
        mutex.assertValidAlignment()

        #if os(Windows)
        InitializeSRWLock(mutex)
        #elseif (compiler(<6.1) && !os(WASI)) || (compiler(>=6.1) && _runtime(_multithreaded))
        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        debugOnly {
            pthread_mutexattr_settype(&attr, .init(PTHREAD_MUTEX_ERRORCHECK))
        }

        let err = pthread_mutex_init(mutex, &attr)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        #endif
    }

    @inlinable
    static func destroy(_ mutex: UnsafeMutablePointer<LockPrimitive>) {
        mutex.assertValidAlignment()

        #if os(Windows)
        // SRWLOCK does not need to be free'd
        #elseif (compiler(<6.1) && !os(WASI)) || (compiler(>=6.1) && _runtime(_multithreaded))
        let err = pthread_mutex_destroy(mutex)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        #endif
    }

    @inlinable
    static func lock(_ mutex: UnsafeMutablePointer<LockPrimitive>) {
        mutex.assertValidAlignment()

        #if os(Windows)
        AcquireSRWLockExclusive(mutex)
        #elseif (compiler(<6.1) && !os(WASI)) || (compiler(>=6.1) && _runtime(_multithreaded))
        let err = pthread_mutex_lock(mutex)
        // Here ae codes according to documentation - https://linux.die.net/man/3/pthread_mutex_lock
        // EINVAL  22
        // EBUSY   16
        // EAGAIN  35
        // EDEADLK 11
        // EPERM   1
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        #endif
    }

    @inlinable
    static func unlock(_ mutex: UnsafeMutablePointer<LockPrimitive>) {
        mutex.assertValidAlignment()

        #if os(Windows)
        ReleaseSRWLockExclusive(mutex)
        #elseif (compiler(<6.1) && !os(WASI)) || (compiler(>=6.1) && _runtime(_multithreaded))
        let err = pthread_mutex_unlock(mutex)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        #endif
    }
}

@usableFromInline
final class LockStorage<Value>: ManagedBuffer<Value, LockPrimitive> {

    @inlinable
    static func create(value: Value) -> Self {
        let buffer = Self.create(minimumCapacity: 1) { _ in
            value
        }
        // Intentionally using a force cast here to avoid a miss compiliation in 5.10.
        // This is as fast as an unsafeDownCast since ManagedBuffer is inlined and the optimizer
        // can eliminate the upcast/downcast pair
        let storage = buffer as! Self

        storage.withUnsafeMutablePointers { _, lockPtr in
            LockOperations.create(lockPtr)
        }

        return storage
    }

    @inlinable
    func lock() {
        self.withUnsafeMutablePointerToElements { lockPtr in
            LockOperations.lock(lockPtr)
        }
    }

    @inlinable
    func unlock() {
        self.withUnsafeMutablePointerToElements { lockPtr in
            LockOperations.unlock(lockPtr)
        }
    }

    @inlinable
    deinit {
        self.withUnsafeMutablePointerToElements { lockPtr in
            LockOperations.destroy(lockPtr)
        }
    }

    @inlinable
    func withLockPrimitive<T>(_ body: (UnsafeMutablePointer<LockPrimitive>) throws -> T) rethrows -> T {
        try self.withUnsafeMutablePointerToElements { lockPtr in
            try body(lockPtr)
        }
    }

    @inlinable
    func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        try self.withUnsafeMutablePointers { valuePtr, lockPtr in
            LockOperations.lock(lockPtr)
            defer { LockOperations.unlock(lockPtr) }
            return try mutate(&valuePtr.pointee)
        }
    }
}

extension LockStorage: @unchecked Sendable {}

/// A threading lock based on `libpthread` instead of `libdispatch`.
///
/// - note: ``NIOLock`` has reference semantics.
///
/// This object provides a lock on top of a single `pthread_mutex_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO. On Windows, the lock is based on the substantially similar
/// `SRWLOCK` type.
public struct PosixLock {
    @usableFromInline
    internal let _storage: LockStorage<Void>

    /// Create a new lock.
    @inlinable
    public init() {
        self._storage = .create(value: ())
    }

    /// Acquire the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    @inlinable
    public func lock() {
        self._storage.lock()
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `lock`, to simplify lock handling.
    @inlinable
    public func unlock() {
        self._storage.unlock()
    }

    @inlinable
    internal func withLockPrimitive<T>(_ body: (UnsafeMutablePointer<LockPrimitive>) throws -> T) rethrows -> T {
        try self._storage.withLockPrimitive(body)
    }
}

extension PosixLock {
    /// Acquire the lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }

    @inlinable
    public func withLockVoid(_ body: () throws -> Void) rethrows {
        try self.withLock(body)
    }
}

extension PosixLock: Sendable {}

extension UnsafeMutablePointer {
    @inlinable
    func assertValidAlignment() {
        assert(UInt(bitPattern: self) % UInt(MemoryLayout<Pointee>.alignment) == 0)
    }
}

@inlinable
internal func debugOnly(_ body: () -> Void) {
    assert(
        {
            body()
            return true
        }()
    )
}
