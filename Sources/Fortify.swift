//
//  Fortify.swift
//  Fortify
//
//  Created by John Holdsworth on 19/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Fortify/Sources/Fortify.swift#27 $
//

import Foundation
import StringIndex
import SwiftRegex
import Popen
import DLKit

internal func hook_assertionFailure(
  _ prefix: StaticString, _ message: StaticString,
  file: StaticString, line: UInt,
  flags: UInt32
) -> Never {
    Fortify.escape(msg: "\(message)", file: file, line: line)
}

internal func hook_assertionFailure(
  _ prefix: StaticString, _ message: String,
  file: StaticString, line: UInt,
  flags: UInt32
) -> Never {
    Fortify.escape(msg: message, file: file, line: line)
}

/// Abstract superclass to maintain ThreadLocal instances.
open class ThreadLocal {
    #if !os(Linux)
    static var keyLock = OS_SPINLOCK_INIT
    #endif

    public required init() {}

    open class var threadKeyPointer: UnsafeMutablePointer<pthread_key_t> {
        fatalError("Subclass responsibility to provide threadKey var")
    }

    public class var threadLocal: Self {
        let keyVar = threadKeyPointer
        #if !os(Linux)
        OSSpinLockLock(&keyLock)
        #endif
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
        #if !os(Linux)
        OSSpinLockUnlock(&keyLock)
        #endif
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

    override open class var threadKeyPointer: UnsafeMutablePointer<pthread_key_t> {
        return UnsafeMutablePointer(&pthreadKey)
    }

    private var stack = [jmp_buf]()
    public var error: Error?

    // Required as Swift assumes it has control of the stack
    static let disableExclusivityChecking: () = {
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

    public static var signalsTrapped = [
        SIGILL: "SIGILL", // Force unwrap of nil etc.
        SIGABRT: "SIGABRT", // Bad cast 5.2
        SIGTRAP: "SIGTRAP", // Bad cast macOS 11
    ]

    public static let installHandlersOnce: Void = {
        // Force unwrap of nil, bad cast etc.
        // macOS 11 abort() seems to send SIGTRAP
        for (signo, sigtxt) in signalsTrapped {
            _ = signal(signo, { (signo: Int32) in
                escape(msg: "Signal \(signalsTrapped[signo] ?? "#\(signo)")")
            })
        }

        #if !os(Linux)
        // For Swift 5.3+, hook _assertionFailures
        if DLKit.appImages.rebind(mapping: [
            "$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF":
            "$s7Fortify21hook_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2ISus6UInt32VtF",
            "$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF":
             "$s7Fortify21hook_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAISus6UInt32VtF"
        ]).count == 0 {
            NSLog("⚠️ Unable to hook _assertionFailure")
        }
        #endif

        _ = disableExclusivityChecking
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
        let trace = "Program has trapped: \(msg) file: \(file), line: \(line)\nStack trace follows:\n\(stackTrace())"
        NSLog(trace)
        escape(withError: NSError(domain: "Fortify", code: -1, userInfo: [
            NSLocalizedDescriptionKey: trace, "file": file, "line": line
        ]))
    }

    /// Escape from current execution context, rewind the stack
    /// and throw error from the last time protect was called.
    /// - Parameter error: object conforming to Error.
    open class func escape(withError error: Error) -> Never {
        let local = threadLocal
        local.error = error

        if local.stack.count == 0 {
            NSLog("Fortify.escape called without matching protect call: \(error)")
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
        // control resumes at set_jump call returning 1
    }

    public class func stackTrace() -> String {
        var trace = ""
        #if os(Linux)
        var syms = [String: [(offset: Int, mangled: String)]]()
        func loadSyms(path: String) -> [(offset: Int, mangled: String)] {
            if syms.index(forKey: path) == nil {
                syms[path] = Popen(cmd: "nm \"\(path)\" | sort")?.compactMap {
                    line -> (offset: Int, mangled: String)? in
                    guard let (offset, mangled): (String, String) =
                            line[#"(\w+) T (.*)$"#],
                          let offset = Int(offset, radix: 16) else { return nil }
                    return (offset, mangled)
                }
            }
            return syms[path] ?? []
        }
        #endif
        for var caller in Thread.callStackSymbols {
            #if !os(Linux)
            let symbolEnd = .last(of: " ") - 2
            let symbolStart = symbolEnd + .last(of: " ") + 1
            let symbolRange = symbolStart ..< symbolEnd
            if let symbol = caller[safe: symbolRange],
                let demangled = demangle(symbol: symbol) {
                caller[symbolRange] = demangled
            }
            #else
            let patcher = #"([^(]+)\(\+0x([^)]+)\) \[([^\]]+)"#
            if let (file, offset, _): (String, String, String) =
                caller[patcher], let off = Int(offset, radix: 16),
               let sym = loadSyms(path: file).filter({ $0.offset <= off }).last {
                let swift = demangle(symbol: sym.mangled) ?? sym.mangled
                caller[patcher] = (file, offset, swift+" + \(off-sym.offset)")
            }
            #endif
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

