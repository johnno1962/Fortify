//
//  Fortify.swift
//  Fortify
//
//  Created by John Holdsworth on 19/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Fortify/Sources/Fortify.swift#17 $
//

import Foundation
import StringIndex
import fishhook

public func hook_assertionFailure(
  _ prefix: StaticString, _ message: StaticString,
  file: StaticString, line: UInt,
  flags: UInt32
) -> Never {
    Fortify.escape(msg: "\(message), file: \(file), line: \(line)")
}

/// Abstract superclass to maintain ThreadLocal instances.
open class ThreadLocal {
    static var keyLock = OS_SPINLOCK_INIT

    public required init() {}

    class var threadKeyPointer: UnsafeMutablePointer<pthread_key_t> {
        fatalError("Subclass responsibility to provide threadKey var")
    }

    class var threadLocal: Self {
        let keyVar = threadKeyPointer
        OSSpinLockLock(&keyLock)
        if keyVar.pointee == 0 {
            let ret = pthread_key_create(keyVar, {
                #if os(Linux) || os(Android)
                Unmanaged<ThreadLocal>.fromOpaque($0!).release()
                #else
                Unmanaged<ThreadLocal>.fromOpaque($0).release()
                #endif
            })
            if ret != 0 {
                fatalError("Could not pthread_key_create: \(String(cString: strerror(ret)))")
            }
        }
        OSSpinLockUnlock(&keyLock)
        if let existing = pthread_getspecific(keyVar.pointee) {
            return Unmanaged<Self>.fromOpaque(existing).takeUnretainedValue()
        }
        else {
            let unmanaged = Unmanaged.passRetained(Self())
            let ret = pthread_setspecific(keyVar.pointee, unmanaged.toOpaque())
            if ret != 0 {
                fatalError("Could not pthread_setspecific: \(String(cString: strerror(ret)))")
            }
            return unmanaged.takeUnretainedValue()
        }
    }
}

@_silgen_name ("setjmp")
public func setjump(_: UnsafeMutablePointer<jmp_buf>) -> Int32

@_silgen_name ("longjmp")
public func longjump(_: UnsafeMutablePointer<jmp_buf>, _: Int32) -> Never

private let empty_buf = [UInt8](repeating: 0, count: MemoryLayout<jmp_buf>.size)

open class Fortify: ThreadLocal {

    static private var pthreadKey: pthread_key_t = 0

    override class var threadKeyPointer: UnsafeMutablePointer<pthread_key_t> {
        return UnsafeMutablePointer(&pthreadKey)
    }

    private var stack = [jmp_buf]()
    public var error: Error?

    // Required as Swift assumes it has control of the stack
    static var disableExclusivityChecking: () = {
        #if os(Android)
        let libName = "libswiftCore.so"
        #else
        let libName: String? = nil
        #endif
        if let stdlibHandle = dlopen(libName, Int32(RTLD_LAZY | RTLD_NOLOAD)),
            let disableExclusivity = dlsym(stdlibHandle, "_swift_disableExclusivityChecking") {
            disableExclusivity.assumingMemoryBound(to: Bool.self).pointee = true
        }
        else {
            NSLog("Could not disable exclusivity, failure likely...")
        }
    }()

    public static let installHandlersOnce: Void = {
        // Force unwrap of nil etc.
        _ = signal(SIGILL, { (signo: Int32) in
            escape(msg: "Signal \(signo)")
        })
        // Bad cast
        _ = signal(SIGABRT, { (signo: Int32) in
            escape(msg: "Signal \(signo)")
        })
        // Bad cast macOS 11
        _ = signal(SIGTRAP, { (signo: Int32) in
            escape(msg: "Signal \(signo)")
        })

        _ = disableExclusivityChecking

        // For Swift 5.3+, hook _assertionFailure
        let failure = "_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2"
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        if let fake = dlsym(RTLD_DEFAULT, "$s7Fortify21hook"+failure+"ISus6UInt32VtF") {
            var rebindings = [rebinding]()
            rebindings.append(rebinding(name: strdup("$ss17"+failure+"HSus6UInt32VtF"),
                replacement: fake, replaced: nil))

            rebind_symbols(&rebindings, rebindings.count)
        }
    }()

    /// Execute the passed-in block assured in the knowledge
    /// any Swift exception will be converted into a throw.
    /// - Parameter block: block to protect execution of
    /// - Throws: Error protocol object often NSError
    /// - Returns: value if block returns value
    open class func protect<T>(block: () throws -> T) throws -> T {
        let local = threadLocal
        _ = installHandlersOnce

        empty_buf.withUnsafeBytes {
            let buf_ptr = $0.baseAddress!.assumingMemoryBound(to: jmp_buf.self)
            local.stack.append(buf_ptr.pointee)
        }

        defer {
            local.stack.removeLast()
        }

        if setjump(&local.stack[local.stack.count-1]) != 0 {
            throw local.error ?? NSError(domain: "Error not available", code: -1, userInfo: nil)
        }

        return try block()
    }

    /// Escape from current execution context, rewind the stack
    /// and throw error from the last time protect was called.
    /// - Parameters:
    ///   - msg: A short message describing the error.
    open class func escape(msg: String, file: StaticString = #file, line: UInt = #line) -> Never {
        let trace = "Program has trapped: \(msg), stack trace follows:\n\(stackTrace())"
        NSLog(trace)
        escape(withError: NSError(domain: "Fortify", code: -1, userInfo: [
            NSLocalizedDescriptionKey: trace,
            "msg": msg, "file": file, "line": line
        ]))
    }

    /// Escape from current execution context, rewind the stack
    /// and throw error from the last time protect was called.
    /// - Parameter error: object conforming to Error.
    open class func escape(withError error: Error) -> Never {
        let local = threadLocal
        local.error = error

        if local.stack.count == 0 {
            NSLog("escape without matching protect call: \(error)")
            #if !os(Android)
            // pthread_exit(nil) just crashes
            var oldState: Int32 = 0
            pthread_setcancelstate(Int32(PTHREAD_CANCEL_ENABLE), &oldState)
            pthread_setcanceltype(Int32(PTHREAD_CANCEL_DEFERRED), &oldState)
            // pthread_cancel() never seems to be implemented
            let cancelled = pthread_cancel(pthread_self())
            if cancelled != 0 {
                NSLog("pthread_cancel() failed: %s", strerror(cancelled))
            }
            sleep(1)
            #endif
            NSLog("cancel/exit not available/implemented or crashes, parking thread")
            Thread.sleep(until: Date.distantFuture)
        }

        longjump(&local.stack[local.stack.count-1], 1)
        NSLog("longjmp() failed, should not get here")
    }

    public class func stackTrace() -> String {
        var trace = ""
        for var caller in Thread.callStackSymbols {
            let symbolEnd = .last(of: " ") - 2
            let symbolStart = symbolEnd + .last(of: " ") + 1
            let symbolRange = symbolStart ..< symbolEnd
            if let symbol = caller[safe: symbolRange],
                let demangled = demangle(symbol: symbol) {
                caller[symbolRange] = demangled
            }

            trace += caller+"\n"
        }
        return trace
    }

    class func demangle(symbol: UnsafePointer<Int8>) -> String? {
        if let demangledNamePtr = _stdlib_demangleImpl(
            symbol, mangledNameLength: UInt(strlen(symbol)),
            outputBuffer: nil, outputBufferSize: nil, flags: 0) {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return nil
    }
}

@_silgen_name("swift_demangle")
private
func _stdlib_demangleImpl(
    _ mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<UInt8>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?

