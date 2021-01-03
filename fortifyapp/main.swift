//
//  main.swift
//  fortifyapp
//
//  Created by John Holdsworth on 26/04/2018.
//

import Foundation
import Fortify

do {
    try Fortify.protect {
        var a: String!
        a = a!
    }
}
catch {
    NSLog("Unwrap error: \(error)")
}

print("Hello, World!")

func f( g: () -> Void ) {
    g()
}

func g( h: () -> Void ) {
    f( g: h )
}

do {
    try Fortify.protect {
        g( h: {
            class B{}
            class C{
                func x(){}
            }
            var b: Any = B()
            var d = b as! C
            d.x()
        })
    }
}
catch {
    print("\(error)")
}

do {
    try Fortify.protect {
        var a: String?
        NSLog(a!)
    }
}
catch {
    print("\(error)")
}

do {
    try Fortify.protect {
        var a: String?
        NSLog(a!)
    }
}
catch {
    print("\(error)")
}

do {
    try Fortify.protect {
        class B{}
        class C{}
        var d = B() as! C
    }
}
catch {
    print("\(error)")
}

do {
    try Fortify.protect {
        class B{}
        class C{}
        var d = B() as! C
    }
}
catch {
    print("\(error)")
}
