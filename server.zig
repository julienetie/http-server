// I'm building a server from this tutorial
// https://blog.orhun.dev/zig-bits-04/
// But I'm trying to understand each line.

// Self explanatory: Standard library
const std = @import("std");

// https://ziglang.org/documentation/master/std/#A;std:http
const http = std.http;

// std.log is a standardized interface for logging which allows for
// the logging of programs and libraries using this interface to be
// formatted and filtered by the implementer of the std.options.logFn
// function.

// When using the simple std.log.info and such, the scope default is
// used implicitly, the default log output function does not print the
// scope for messages with default as the scope. In order to produce log
// messages with a different scope a scoped log needs to be created.
const log = std.log.scoped(.server);

// Localhost
const server_addr = "127.0.0.1";

// Port
const server_port = 3333;

// - server             *http.Server                A pointer to the HTTP Server implementation.
// - allocator          std.mem.Allocator           It serves as a contract that different
//                                                  allocator implementations must adhere to,
//                                                  ensuring consistency and flexibility in
//                                                  memory management.
// - Return void                                    ! Returns an error or nothing
fn serve(server: *http.Server, allocator: std.mem.Allocator) !void {
    outer: while (true) { // Label with infinite loop
        var response = try server.accept(.{ // server.accept waits for an incoming connection and returns the Server.Response object
            .allocator = allocator, // try handels errors
        }); // .{ specifies params to the accept fn
        defer response.deinit(); // Deferred deinitialization

        // The loop continues until the response.reset() method returns .closing
        while (response.reset() != .closing) {
            // waiting for something to happen on the response object.
            response.wait() catch |err| switch (err) {
                // If the exception is of type error.HttpHeadersInvalid, the code continues to the next iteration of the outer loop
                error.HttpHeadersInvalid => continue :outer,
                // If the exception is of type error.EndOfStream, the code also continues to the next iteration of the outer while loop.
                error.EndOfStream => continue,
                // For any other type of exception, the code returns the exception
                else => return err,
            };
            try handleRequest(&response, allocator);
        }
    }
}

fn handleRequest(response: *http.Server.Response, allocator: std.mem.Allocator) !void {
    // @ is a built-in function
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body. 8192 serves as a buffer size for reading the response body
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    if (std.mem.startsWith(u8, response.request.target, "/get")) {

        // checking whether a specific substring ("?chunked")
        //  is assumed to be a byte slice (probably representing the target of an HTTP request).
        if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
            response.transfer_encoding = .chunked;
        } else {
            response.transfer_encoding = .{ .content_length = 10 };
        }

        // Set "content-type" header to "text/plain".
        try response.headers.append("content-type", "text/plain");

        // Write the response body.
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll("Zig ");
            try response.writeAll("Bits!\n");
            try response.finish();
        }
    } else {
        // Set the response status to 44 (not found).
        response.status = .not_found;
        try response.do();
    }
}

pub fn main() !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Creates a new HTTP Server with allocator
    // reuse_address = true allows the server to reuse the same address
    // After it has been closed.
    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit(); // Self explanatory, called when fn execution finishes.

    // Log the server address and port.
    log.info("Server is running at {s}:{d}", .{ server_addr, server_port });

    // Parse the server address.
    const address = std.net.Address.parseIp(server_addr, server_port) catch unreachable;
    try server.listen(address);

    // Starts the server and listens for incomming connections
    // - server          Mem address of server
    // - allocator       Mem allocator
    serve(&server, allocator) catch |err| { // If error occures catch block executes
        log.err("server error: {}\n", .{err});
        // Print a stack trace to the console when an error occurs.
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}
