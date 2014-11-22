//
//  HttpServer.swift
//
//  Created by Damian Kolakowski on 05/06/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation

class HttpServer
{
    // 声明一个输入为 HttpRequest 类型，返回 HttpResponse 类型的函数别名
    typealias Handler = HttpRequest -> HttpResponse
    
    // 定义一个数组，每个数组元素是由 (NSRegularExpression, Handler) 元祖组成
    var handlers: [(expression: NSRegularExpression, handler: Handler)] = []
    var acceptSocket: CInt = -1
    
    let matchingOptions = NSMatchingOptions(0)
    let expressionOptions = NSRegularExpressionOptions(0)
    
    // 下标变量，通过 path 值，找到 Handler
    subscript (path: String) -> Handler? {
        get {
            return nil
        }
        set ( newValue ) {
            if let regex = NSRegularExpression(pattern: path, options: expressionOptions, error: nil) {
                if let newHandler = newValue {
                    handlers.append(expression: regex, handler: newHandler)
                }
            }
        }
    }
    
    // 返回路由列表
    func routes() -> [String] { return map(handlers, { $0.0.pattern }) }

    // 运行 server, 默认 server 接口为 8080, 传入捕获错误信息指针
    func start(listenPort: in_port_t = 8080, error: NSErrorPointer = nil) -> Bool {
        releaseAcceptSocket()
        // 监听 socket 端口
        if let socket = Socket.tcpForListen(port: listenPort, error: error) {
            // 如果 socket 连接成功，并且成功监听到端口，那么设置该 socket 文件描述符到 acceptSocket
            acceptSocket = socket
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
                // 接收 socket 连接
                while let socket = Socket.acceptClientSocket(self.acceptSocket) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
                        let parser = HttpParser()
                        // 解析 HTTP 信息： url, method, headers, responseData
                        while let request = parser.nextHttpRequest(socket) {
                            let keepAlive = parser.supportsKeepAlive(request.headers)
                            // 通过request 请求的地址找到该地址对应的 Handler 信息
                            if let (expression, handler) = self.findHandler(request.url) {
                                let capturedUrlsGroups = self.captureExpressionGroups(expression, value: request.url)
                                let updatedRequest = HttpRequest(url: request.url, urlParams: request.urlParams, method: request.method, headers: request.headers, body: request.body, capturedUrlGroups: capturedUrlsGroups)
                                HttpServer.writeResponse(socket, response: handler(updatedRequest), keepAlive: keepAlive)
                            } else {
                                HttpServer.writeResponse(socket, response: HttpResponse.NotFound, keepAlive: keepAlive)
                            }
                            if !keepAlive { break }
                        }
                        Socket.release(socket)
                    })
                }
                self.releaseAcceptSocket()
            })
            return true
        }
        return false
    }
    
    func findHandler(url:String) -> (NSRegularExpression, Handler)? {
        return filter(self.handlers, {
            $0.0.numberOfMatchesInString(url, options: self.matchingOptions, range: HttpServer.asciiRange(url)) > 0
        }).first
    }
    
    func captureExpressionGroups(expression: NSRegularExpression, value: String) -> [String] {
        var capturedGroups = [String]()
        if let result = expression.firstMatchInString(value, options: matchingOptions, range: HttpServer.asciiRange(value)) {
            let nsValue: NSString = value
            for var i = 1 ; i < result.numberOfRanges ; ++i {
                if let group = nsValue.substringWithRange(result.rangeAtIndex(i)).stringByRemovingPercentEncoding {
                    capturedGroups.append(group)
                }
            }
        }
        return capturedGroups
    }
    
    class func asciiRange(value: String) -> NSRange {
        return NSMakeRange(0, value.lengthOfBytesUsingEncoding(NSASCIIStringEncoding))
    }
    
    // HttpServer 向 socket 中写入 response 信息
    class func writeResponse(socket: CInt, response: HttpResponse, keepAlive: Bool) {
        println(">> HttpServer.writeResponse()")
        Socket.writeStringUTF8(socket, string: "HTTP/1.1 \(response.statusCode()) \(response.reasonPhrase())\r\n")
        if let body = response.body() {
            Socket.writeStringASCII(socket, string: "Content-Length: \(body.length)\r\n")
        } else {
            Socket.writeStringASCII(socket, string: "Content-Length: 0\r\n")
        }
        if keepAlive {
            Socket.writeStringASCII(socket, string: "Connection: keep-alive\r\n")
        }
        for (name, value) in response.headers() {
            Socket.writeStringASCII(socket, string: "\(name): \(value)\r\n")
        }
        Socket.writeStringASCII(socket, string: "\r\n")
        if let body = response.body() {
            Socket.writeData(socket, data: body)
        }
    }
    
    // 停止 server
    func stop() {
        releaseAcceptSocket()
    }
    
    // 如果处于 acceptSocket 状态，则停止 socket 服务
    func releaseAcceptSocket() {
        if ( acceptSocket != -1 ) {
            Socket.release(acceptSocket)
            acceptSocket = -1
        }
    }
}

