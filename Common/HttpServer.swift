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
            for (expression, handler) in handlers {
                let numberOfMatches: Int = expression.numberOfMatchesInString(path, options: matchingOptions, range: NSMakeRange(0, path.lengthOfBytesUsingEncoding(NSASCIIStringEncoding)))
                if ( numberOfMatches > 0 ) {
                    return handler
                }
            }
            return nil
        }
        set ( newValue ) {
            if let regex: NSRegularExpression = NSRegularExpression.regularExpressionWithPattern(path, options: expressionOptions, error: nil) {
                if let newHandler = newValue {
                    handlers.append(expression: regex, handler: newHandler)
                }
            }
        }
    }
    
    // 下标变量
    subscript (path: String) -> String {
        get {
            return path
        }
        set ( directoryPath ) {
            if let regex = NSRegularExpression.regularExpressionWithPattern(path, options: expressionOptions, error: nil) {
                handlers.append(expression: regex, handler: { request in
                    // 返回和正则表达式匹配的第一个值
                    let result = regex.firstMatchInString(request.url, options: self.matchingOptions, range: NSMakeRange(0, request.url.lengthOfBytesUsingEncoding(NSASCIIStringEncoding)))
                    let nsPath: NSString = request.url
                    let filesPath = directoryPath.stringByExpandingTildeInPath
                        .stringByAppendingPathComponent(nsPath.substringWithRange(result!.rangeAtIndex(1)))
                    if let fileBody = String.stringWithContentsOfFile(filesPath, encoding: NSASCIIStringEncoding, error: nil) {
                        println(fileBody)
                        return HttpResponse.OK(.RAW(fileBody))
                    }
                    return HttpResponse.NotFound
                })
            }
        }
    }
    
    // 返回路由列表
    func routes() -> Array<String> {
        var results = [String]()
        for (expression,_) in handlers { results.append(expression.pattern) }
        return results
    }
    
    // 运行 server, 默认 server 接口为 8080, 传入错误指针
    func start(listenPort: in_port_t = 8080, error:NSErrorPointer = nil) -> Bool {
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
                            // 通过下标变量找到该地址对应的 Handler 信息
                            if let handler: Handler = self[request.url] {
                                HttpServer.writeResponse(socket, response: handler(request), keepAlive: keepAlive)
                            } else {
                                HttpServer.writeResponse(socket, response: HttpResponse.NotFound, keepAlive: keepAlive)
                            }
                            if !keepAlive { break }
                        }
                        Socket.release(socket)
                    });
                }
                self.releaseAcceptSocket()
            });
            return true
        }
        return false
    }
    
    // HttpServer 向 socket 中写入 response 信息
    class func writeResponse(socket: CInt, response: HttpResponse, keepAlive: Bool) {
        println(">> HttpServer.writeResponse()")
        Socket.writeStringUTF8(socket, string: "HTTP/1.1 \(response.statusCode()) \(response.reasonPhrase())\r\n")
        let messageBody = response.body()
        if let body = messageBody {
            if let nsdata = body.dataUsingEncoding(NSUTF8StringEncoding) {
                Socket.writeStringUTF8(socket, string: "Content-Length: \(nsdata.length)\r\n")
            }
        } else {
            Socket.writeStringUTF8(socket, string: "Content-Length: 0\r\n")
        }
        if keepAlive {
            Socket.writeStringUTF8(socket, string: "Connection: keep-alive\r\n")
        }
        //Socket.writeStringUTF8(socket, string: "Content-Type: text/html; charset=UTF-8\r\n")
        for (name, value) in response.headers() {
            Socket.writeStringUTF8(socket, string: "\(name): \(value)\r\n")
        }
        Socket.writeStringUTF8(socket, string: "\r\n")
        if let body = messageBody {
            Socket.writeStringUTF8(socket, string: body)
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

