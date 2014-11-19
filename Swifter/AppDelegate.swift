//
//  AppDelegate.swift
//  TestSwift
//
//  Created by Damian Kolakowski on 05/06/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var server: HttpServer?
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: NSDictionary?) -> Bool {
        let server = demoServer("/Users/wshan/Workspace/swifter")
        self.server = server
        var error: NSError?
        if server.start(error: &error) {
            println("Server start error: \(error)")
        }
        return true
    }
}

