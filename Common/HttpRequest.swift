//
//  HttpRequest.swift
//  Swifter
//
//  Created by Damian Kolakowski on 19/08/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation

// HttpRequest 结构体，定义了 HTTP 请求的地址，方法名， header 信息，和请求返回数据
struct HttpRequest {
    let url: String
    let method: String
    let headers: Dictionary<String, String>
	let responseData: NSData?
}
