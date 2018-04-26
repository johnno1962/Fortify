# Fortify - A more robust Swift

Fortify is a small, single file, library allows Swift to be more robust in the face of what are currently fatal errors such as forced unwrap of nil or casting errors.

Use Fortify as you would existing Swift exceptions except that exceptions are generated automatically for Swift errors. Errors are thrown up the stack manually without intermediate functions being declared as throwing. An example:

```Swift
import Fortify

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

In the example, the forced unwrap of nil will generate an exception rather than terminate the application.

### Note:
This form of exception throwing is rather ill-mannered in that it will not clean up live objects, operations or system resources in use in intermediate frames. This approach is suggested where it is important not to crash such as in development of Swift application servers. No representation about the reliability of an application once an error has occurred is made though in general the undesirable effects should be limited to leaking of memory and system resources. A more detailed write-up of how Fortify works and its use of setjmp/longjmp is [here](http://johnholdsworth.com/fortify.html).
