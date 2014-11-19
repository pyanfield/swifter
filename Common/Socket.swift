//
//  Socket.swift
//
//  Created by Damian Kolakowski on 05/06/14.
//  Copyright (c) 2014 Damian Kołakowski. All rights reserved.
//

import Foundation

/* Low level routines for POSIX sockets */

struct Socket {
    
    // 返回 socket 错误信息
    static func socketLastError(reason:String) -> NSError {
        let errorCode = errno
        if let errorText = String.fromCString(UnsafePointer(strerror(errorCode))) {
            return NSError(domain: "SOCKET", code: Int(errorCode), userInfo: [NSLocalizedFailureReasonErrorKey : reason, NSLocalizedDescriptionKey : errorText])
        }
        return NSError(domain: "SOCKET", code: Int(errorCode), userInfo: nil)
    }
    
    // 建立 socket 连接，监听 port 端口
    static func tcpForListen(port: in_port_t = 8080, error:NSErrorPointer = nil) -> CInt? {
        // socket 数据传输是一种特殊的I/O，Socket也是一种文件描述符。
        // int socket(int domain, int type, int protocol);
        // domain 指明所使用的协议族，通常为PF_INET 即 AF_INET，表示互联网协议族（TCP/IP协议族）。
        // type参数指定socket的类型。
        // 常用的Socket类型有两种：流式Socket （SOCK_STREAM）和数据报式Socket（SOCK_DGRAM）。
        // 流式是一种面向连接的Socket，针对于面向连接的TCP服务应用；
        // 数据报式Socket是一种无连接的Socket，对应于无连接的UDP服务应用。
        // protocol通常赋值 "0"
        // 该函数返回一个整型的Socket描述符，随后的连接建立、数据传输等操作都是通过该Socket实现的。
        let s = socket(AF_INET, SOCK_STREAM, 0)
        if ( s == -1 ) {
            if error != nil { error.memory = socketLastError("socket(...) failed.") }
            return nil
        }
        var value: Int32 = 1;
        // setsockopt()函数用于任意类型、任意状态套接口的设置选项值。
        // 尽管在不同协议层上存在选项，但本函数仅定义了最高的“套接口”层次上的选项。
        // int setsockopt(int socket, int level, int option_name, const void *option_value, socklen_t option_len);
        // socket : 一个打开套接字文件描述符
        // level : level：选项定义的层次
        //            SOL_SOCKET: 基本套接口
        //            IPPROTO_IP: IPv4套接口
        //            IPPROTO_IPV6: IPv6套接口
        //            IPPROTO_TCP: TCP套接口
        // option_name : 需要设置的选项名
        //            SO_REUSERADDR 允许重用本地地址和端口 int,充许绑定已被使用的地址（或端口号）,参考bind()
        // option_value : 指针，指向存放选项待设置的新值的缓冲区
        // option_len : opetion_value 缓冲区的长度
        // 如果没有错误发生，则返回 0
        if ( setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(sizeof(Int32))) == -1 ) {
            release(s)
            if error != nil { error.memory = socketLastError("setsockopt(...) failed.") }
            return nil
        }
        nosigpipe(s)
        
        // 由于Microsoft TCP/IP套接字开发人员的工具箱仅支持internet地址字段，而实际填充字段的每一部分则遵循sockaddr_in数据结构
        var addr = sockaddr_in(sin_len: __uint8_t(sizeof(sockaddr_in)),
                            sin_family: sa_family_t(AF_INET),     // adress family
                              sin_port: port_htons(port),       // port number
                              sin_addr: in_addr(s_addr: inet_addr("0.0.0.0")),   // internet address
                              sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        
        // sockaddr 是一个通用地址结构，用于存储参与（IP）Windows套接字通信的计算机上的一个internet协议（IP）地址。
        // 为了统一地址结构的表示方法，统一接口函数，使得不同的地址结构可以被bind()、connect()、recvfrom()、sendto()等函数调用。
        var sock_addr = sockaddr(sa_len: 0,
                              sa_family: 0,        // address family
                                sa_data: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))   // address value
        // 内存复制，从 addr 地址复制到 sock_addr
        memcpy(&sock_addr, &addr, UInt(sizeof(sockaddr_in)))
        
        // int bind(int socket, const struct sockaddr *address, socklen_t address_len);
        // 将一本地地址与一套接口捆绑。本函数适用于未连接的数据报或流类套接口，在connect()或listen()调用前使用。
        // 当用socket()创建套接口后，它便存在于一个名字空间（地址族）中，但并未赋名。
        // bind()函数通过给一个未命名套接口分配一个本地名字来为套接口建立本地捆绑（主机地址/端口号。
        if ( bind(s, &sock_addr, socklen_t(sizeof(sockaddr_in))) == -1 ) {
            release(s)
            if error != nil { error.memory = socketLastError("bind(...) failed.") }
            return nil
        }
        // int listen(int socket, int backlog);
        // backlog : 等待连接队列的最大长度。
        // 创建一个套接口并监听申请的连接。
        if ( listen(s, 20 /* max pending connection */ ) == -1 ) {
            release(s)
            if error != nil { error.memory = socketLastError("listen(...) failed.") }
            return nil
        }
        return s
    }
    
    // 向 socket 文件描述符中写入 string 信息
    static func writeStringUTF8(socket: CInt, string: String, error:NSErrorPointer = nil) -> Bool {
        println(">> Socket.writeStringUTF8: \(string)")
        var sent = 0;
        if let nsdata = string.dataUsingEncoding(NSUTF8StringEncoding)
		{
			let unsafePointer = UnsafePointer<UInt8>(nsdata.bytes)
			while ( sent < nsdata.length ) {
                // ssize_t write(int fildes, const void *buf, size_t nbyte);
                // The write() function attempts to write nbyte bytes from the buffer pointed to by buf to the file associated with the open file descriptor, fildes.
                // If nbyte is 0, write() will return 0 and have no other results if the file is a regular file; otherwise, the results are unspecified.
                // Upon successful completion, write() and pwrite() will return the number of bytes actually written to the file associated with fildes. This number will never be greater than nbyte. Otherwise, -1 is returned and errno is set to indicate the error.
                // Write 函数将 buf 中的 nbyte 字节内容写入到文件描述符中，成功返回写的字节数，失败返回-1.并设置errno 变量。
                // write 的返回值大于0，表示写了部分数据或者是全部的数据，这样用一个while循环不断的写入数据，但是循环过程中的buf参数和nbytes参数是我们自己来更新的，也就是说，网络编程中写函数是不负责将全部数据写完之后再返回的，说不定中途就返回了！
				let s = write(socket, unsafePointer + sent, UInt(nsdata.length - sent))
				if ( s <= 0 ) {
					if error != nil { error.memory = socketLastError("write(\(string)) failed.") }
					return false
				}
				sent += s
			}
		}
        return true
    }
    
    // 接收新的连接到 socket 上
    static func acceptClientSocket(socket: CInt, error:NSErrorPointer = nil) -> CInt? {
        var addr = sockaddr(sa_len: 0,
                         sa_family: 0,
                           sa_data: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        var len: socklen_t = 0
        // int accept (int socket, struct sockaddr *address, socklen_t *address_len);
        // 接收一个新的连接到 socket 上
        let clientSocket = accept(socket, &addr, &len)
        if ( clientSocket != -1 ) {
            Socket.nosigpipe(clientSocket)
            return clientSocket
        }
        if error != nil { error.memory = socketLastError("accept(...) failed.") }
        return nil
    }
    
    // 屏蔽 SIGPIPE 信号，防止因为有电话接入或者程序暂停导致程序的崩溃
    static func nosigpipe(socket: CInt) {
        // prevents crashes when blocking calls are pending and the app is paused ( via Home button )
        var no_sig_pipe: Int32 = 1;
        // 直接屏蔽SIGPIPE信号,在SOCKET中用SO_NOSIGPIPE进行屏蔽.
        // 写网络程序时候, 当向对方wrtie数据时候对方主动close了连接, 会产生SIGPIPE信号, 如果不对这个信号处理程序就会退出或者也可以说崩掉了, 所以一般简单处理就是忽略掉这个信号, signal(SIGPIPE, SIG_IGN)
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(sizeof(Int32)));
    }
    
    static func port_htons(port: in_port_t) -> in_port_t {
        let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
        return isLittleEndian ? _OSSwapInt16(port) : port
    }
    
    // 关闭 socket 的发送和接收操作，关闭文件描述符
    static func release(socket: CInt) {
        // 关闭 socket 的发送和接收操作
        // http://pubs.opengroup.org/onlinepubs/007908799/xns/shutdown.html
        shutdown(socket, SHUT_RDWR)
        // 关闭文件描述符
        // http://pubs.opengroup.org/onlinepubs/7908799/xsh/close.html
        close(socket)
    }
}

// unistd.h - standard symbolic constants and types
// http://pubs.opengroup.org/onlinepubs/7908799/xsh/unistd.h.html
// sys/socket.h - Internet Protocol family
// http://pubs.opengroup.org/onlinepubs/007908799/xns/syssocket.h.html
// netinet/in.h - Internet address family
// http://pubs.opengroup.org/onlinepubs/009695399/basedefs/netinet/in.h.html
