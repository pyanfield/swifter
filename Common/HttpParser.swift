//
//  HttpParser.swift
//
//  Created by Damian Kolakowski on 05/06/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation

class HttpParser {
    
    class func err(reason:String) -> NSError {
        return NSError(domain: "HTTP_PARSER", code: 0, userInfo:[NSLocalizedFailureReasonErrorKey : reason])
    }

    // 获取 HTTP 的请求地址，请求方法，请求的header ，和返回数据的信息，然后返回 HttpRequest 结构体
    func nextHttpRequest(socket: CInt, error:NSErrorPointer = nil) -> HttpRequest? { //(String, String, Dictionary<String, String>)? {
        if let statusLine = nextLine(socket, error: error) {
            println(">> statusLine : \(statusLine)")
            // [GET, /json, HTTP/1.1]
            let statusTokens = split(statusLine, { $0 == " " })
            if ( statusTokens.count < 3 ) {
                if error != nil { error.memory = HttpParser.err("Invalid status line: \(statusLine)") }
                return nil
            }
            let method = statusTokens[0]
            let path = statusTokens[1]
            let urlParams = extractUrlParams(path)
            // TODO extract query parameters
            if let headers = nextHeaders(socket, error: error) {
                // TODO detect content-type and handle:
                // 'application/x-www-form-urlencoded' -> Dictionary
                // 'multipart' -> Dictionary
                if let contentSize = headers["content-length"]?.toInt() {
                    let body = nextBody(socket, size: contentSize, error: error)
                    return HttpRequest(url: path, urlParams: urlParams, method: method, headers: headers, body: body, capturedUrlGroups: [])
                }
                return HttpRequest(url: path, urlParams: urlParams, method: method, headers: headers, body: nil, capturedUrlGroups: [])
            }
        }
        return nil
    }

    private func extractUrlParams(url: String) -> [(String, String)] {
        if let query = split(url, { $0 == "?" }).last {
            return map(split(query, { $0 == "&" }), { (param:String) -> (String, String) in
                let tokens = split(param, { $0 == "=" })
                if tokens.count >= 2 {
                    let key = tokens[0].stringByRemovingPercentEncoding
                    let value = tokens[1].stringByRemovingPercentEncoding
                    if key != nil && value != nil { return (key!, value!) }
                }
                return ("","")
            })
        }
        return []
    }
    
    private func nextBody(socket: CInt, size: Int , error:NSErrorPointer) -> String? {
        var body = ""
        var counter = 0;
        while ( counter < size ) {
            let c = nextUInt8(socket)
            if ( c < 0 ) {
                if error != nil { error.memory = HttpParser.err("IO error while reading body") }
                return nil
            }
            body.append(UnicodeScalar(c))
            counter++;
        }
        return body
    }
    
    // 返回 HTTP 请求的 header 信息
    private func nextHeaders(socket: CInt, error:NSErrorPointer) -> Dictionary<String, String>? {
        var headers = Dictionary<String, String>()
        while let headerLine = nextLine(socket, error: error) {
            if ( headerLine.isEmpty ) {
                return headers
            }
            let headerTokens = split(headerLine, { $0 == ":" })
            if ( headerTokens.count >= 2 ) {
                // RFC 2616 - "Hypertext Transfer Protocol -- HTTP/1.1", paragraph 4.2, "Message Headers":
                // "Each header field consists of a name followed by a colon (":") and the field value. Field names are case-insensitive."
                // We can keep lower case version.
                let headerName = headerTokens[0].lowercaseString
                let headerValue = headerTokens[1].stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
                if ( !headerName.isEmpty && !headerValue.isEmpty ) {
                    headers.updateValue(headerValue, forKey: headerName)
                }
            }
        }
        return nil
    }

    private func nextUInt8(socket: CInt) -> Int {
        var buffer = [UInt8](count: 1, repeatedValue: 0);
        // ssize_t recv(int socket, void *buffer, size_t length, int flags);
        // receive a message from a connected socket
        // 从连接的 socket 上接收信息
        // socket : 是接受数据的socket描述符；
        // buffer : 是存放接收数据的缓冲区；
        // length : 是缓冲的长度；
        // flags : 是一个标志位可以是 0 或者一个组合。
        // MSG_DONTWAIT 在 rece(), send() 表示使用非阻塞的方式读取和发送消息
        // Recv()返回实际上接收的字节数，当出现错误时，返回-1并置相应的errno值。
        let next = recv(socket, &buffer, UInt(buffer.count), 0)
        // 如果接收过程出现失败，则返回
        if next <= 0 { return next }
        return Int(buffer[0])
    }
    
    private func nextLine(socket: CInt, error:NSErrorPointer) -> String? {
        var characters: String = ""
        var n = 0
        do {
            n = nextUInt8(socket)
            // "\r" = Character(UnicodeScalar(13)),回车符号
            // "\n" = Character(UnicodeScalar(10)),换行符
            if ( n > 13 /* CR */ ) { characters.append(Character(UnicodeScalar(n))) }
        } while ( n > 0 && n != 10 /* NL */)
        
        if ( n == -1 && characters.isEmpty ) {
            if error != nil { error.memory = Socket.socketLastError("recv(...) failed.") }
            return nil
        }
        // 返回的是 method path http_version 比如 GET /json HTTP/1.1
        return characters
    }
    
    // 解析 header 中是否有 keep-alive 信息
    func supportsKeepAlive(headers: Dictionary<String, String>) -> Bool {
        if let value = headers["connection"] {
            return "keep-alive" == value.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()).lowercaseString
        }
        return false
    }
}
