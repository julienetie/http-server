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
const server_address = "127.0.0.1";

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

        while (response.reset() != .closing) {
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };
            // try handleRequest(&response, allocator);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Creates a new HTTP Server with allocator
    // reuse_address = true allows the server to reuse the same address
    // After it has been closed.
    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit(); // Self explanatory, called when fn execution finishes.

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
