//
//  Fortify.swift
//  Fortify
//
//  Created by John Holdsworth on 19/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Fortify/Sources/Fortify.swift#8 $
//

import Foundation
import StringIndex

open class ThreadLocal {
    public required init() {
    }

    public class func getThreadLocal<T: ThreadLocal>(ofClass: T.Type,
                         keyVar: UnsafeMutablePointer<pthread_key_t>) -> T {
        let needsKey = keyVar.pointee == 0
        if needsKey {
            let ret = pthread_key_create(keyVar, {
                #if os(Linux) || os(Android)
                Unmanaged<ThreadLocal>.fromOpaque($0!).release()
                #else
                Unmanaged<ThreadLocal>.fromOpaque($0).release()
                #endif
            })
            if ret != 0 {
                NSLog("Could not pthread_key_create: %s", strerror(ret))
            }
        }
        if let existing = pthread_getspecific(keyVar.pointee) {
            return Unmanaged<T>.fromOpaque(existing).takeUnretainedValue()
        }
        else {
            let unmanaged = Unmanaged.passRetained(T())
            let ret = pthread_setspecific(keyVar.pointee, unmanaged.toOpaque())
            if ret != 0 {
                NSLog("Could not pthread_setspecific: %s", strerror(ret))
            }
            return unmanaged.takeUnretainedValue()
        }
    }
}

@_silgen_name ("setjmp")
public func setjump(_: UnsafeMutablePointer<jmp_buf>!) -> Int32

@_silgen_name ("longjmp")
public func longjump(_: UnsafeMutablePointer<jmp_buf>!, _: Int32) -> Never

private let empty_buf = [UInt8](repeating: 0, count: MemoryLayout<jmp_buf>.size)

open class Fortify: ThreadLocal {

    static private var pthreadKey: pthread_key_t = 0

    open class var threadLocal: Fortify {
        return getThreadLocal(ofClass: Fortify.self, keyVar: &pthreadKey)
    }

    private var stack = [jmp_buf]()
    public var error: Error?

    // Required as Swift assumes it has control of the stack
    open class func disableExclusivityChecking() {
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
    }

    public static let installHandlerOnce: Void = {
        _ = signal(SIGILL, { (signo: Int32) in
            Fortify.escape(msg: "Signal \(signo)")
        })
        _ = signal(SIGABRT, { (signo: Int32) in
            Fortify.escape(msg: "Signal \(signo)")
        })

        disableExclusivityChecking()
    }()

    open class func exec<T>( block: () throws -> T ) throws -> T {
        _ = installHandlerOnce
        let local = threadLocal

        empty_buf.withUnsafeBytes {
            let buf_ptr = $0.baseAddress!.assumingMemoryBound(to: jmp_buf.self)
            local.stack.append(buf_ptr.pointee)
        }

        defer {
            local.stack.removeLast()
        }

        let stack = local.stack.withUnsafeMutableBufferPointer { $0.baseAddress }
        if setjump(stack! + (local.stack.count-1)) != 0 {
            throw local.error ?? NSError(domain: "Error not available", code: -1, userInfo: nil)
        }

        return try block()
    }

    open class func escape(msg: String, file: StaticString = #file, line: UInt = #line) -> Never {
        let trace = "Program has trapped: \(msg), stack trace follows:\n\(stackTrace())"
        NSLog(trace)
        escape(withError: NSError(domain: "Fortify", code: -1, userInfo: [
            NSLocalizedDescriptionKey: trace,
            "msg": msg, "file": file, "line": line
        ]))
    }

    open class func escape(withError error: Error) -> Never {
        let local = threadLocal
        local.error = error

        if local.stack.count == 0 {
            NSLog("escape without matching exec call: \(error)")
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

        let stack = local.stack.withUnsafeMutableBufferPointer { $0.baseAddress }
        longjump(stack! + (local.stack.count-1), 1)
        NSLog("longjmp() failed, should not get here")
    }

    public class func stackTrace() -> String {
        var trace = ""
        for var caller in Thread.callStackSymbols {
            if let offsetStart = caller.lastIndex(of: " "),
                let symEnd = (offsetStart-2).index(in: caller),
                let symStart = caller[..<symEnd].lastIndex(of: " "),
                let demangled = demangle(symbol: caller[symStart+1 ..< symEnd]) {
                caller[symStart+1 ..< symEnd] = demangled
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

