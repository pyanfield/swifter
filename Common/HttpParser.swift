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
            if let headers = nextHeaders(socket, error: error) {
                println(">> headers : \(headers)")
                var requestBody = ""
                while let line = nextLine(socket, error: error) {
                    if line.isEmpty {
                        break
                    }
                    requestBody += line
                }
                println(">> requestBody : \(requestBody)")
                let body = requestBody.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
                return HttpRequest(url: path, method: method, headers: headers, body: body, capturedUrlGroups: [])
            }
        }
        return nil
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
                let headerValue = headerTokens[1]
                if ( !headerName.isEmpty && !headerValue.isEmpty ) {
                    headers.updateValue(headerValue, forKey: headerName)
                }
            }
        }
        return nil
    }
    
    // 初始化一个含有 1024 个元素的 UInt8 数组，每个元素的值为 0
    var recvBuffer = [UInt8](count: 1024, repeatedValue: 0)
    var recvBufferSize: Int = 0
    var recvBufferOffset: Int = 0
    
    private func nextUInt8(socket: CInt) -> Int {
        if ( recvBufferSize == 0 || recvBufferOffset == recvBuffer.count ) {
            recvBufferOffset = 0
            
            // ssize_t recv(int socket, void *buffer, size_t length, int flags);
            // receive a message from a connected socket
            // 从连接的 socket 上接收信息
            // socket : 是接受数据的socket描述符；
            // buffer : 是存放接收数据的缓冲区；
            // length : 是缓冲的长度；
            // flags : 是一个标志位可以是 0 或者一个组合。 
            // MSG_DONTWAIT 在 rece(), send() 表示使用非阻塞的方式读取和发送消息
            // Recv()返回实际上接收的字节数，当出现错误时，返回-1并置相应的errno值。
            recvBufferSize = recv(socket, &recvBuffer, UInt(recvBuffer.count), 0)
            
            // 如果接收过程出现失败，则返回
            if ( recvBufferSize <= 0 ) { return recvBufferSize }
            
            // 如果实际接收的字节数小于接收数据缓冲区的大小，则将缓冲区的其它数值置 0
            if recvBufferSize < recvBuffer.count
            {
                recvBuffer[recvBufferSize] = 0
            }
        }
        let returnValue = recvBuffer[recvBufferOffset]
        recvBufferOffset++
        return Int(returnValue)
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
