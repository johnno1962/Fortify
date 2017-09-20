# Fortify - A more robust Swift

Fortify is a small, single file, library that in conjunction with minor change to the Swift's standard library allows it to be more robust in the face of what are currently fatal errors such as forced unwrap of nil.

Use Fortify as you would existing Swift exceptions except that exceptions are generated automatically for Swift errors. Errors can also be thrown up the stack manually without intermediate functions being declared as throwing. An example:

```Swift
do {
    try Fortify.exec {
        var a: String!
        a = a!
    }
}
catch {
    NSLog("Unwrap error: \(error)")
}
```

The forced unwrap of nil will generate an exception rather than terminate the application. To use Fortify you need to use an Xcode toolchain that has been slightly modified to provide a hook to intercept errors [available here](http://johnholdsworth.com/swift-LOCAL-2017-09-20-a-osx.tar.gz).

### Note:
This form of exception throwing is rather ill-mannered in that it will not clean up live objects, operations or system resources in use in intermediate frames. This approach is suggested where it is important not to crash such as in development of Swift application servers. No representation about the reliability of an application once an error has occurred is made though in general the undesirable effects should be limited to leaking of memory and system resources. A more detailed write-up of how Fortify works and its use of setjmp/longjmp is [here](http://johnholdsworth.com/fortify.html).
