//
//  Handlers.swift
//  Swifter
//
//  Created by Damian Kolakowski on 14/11/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation

class HttpHandlers {
    
    // 实现静态文件处理
    class func directory(dir: String) -> ( HttpRequest -> HttpResponse ) {
        return { request in
            if let localPath = request.capturedUrlGroups.first {
                let filesPath = dir.stringByExpandingTildeInPath.stringByAppendingPathComponent(localPath)
                if let fileBody = String(contentsOfFile: filesPath, encoding: NSASCIIStringEncoding, error: nil) {
                    return HttpResponse.OK(.RAW(fileBody))
                }
            }
            return HttpResponse.NotFound
        }
    }
}