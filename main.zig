var buffer: [1024]u8 = undefined;
const stdout_file = std.fs.File.stdout();
var stdout_writer = stdout_file.writer(&buffer);
const stdout = &stdout_writer.interface;

var stderr_buffer: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) @panic("memory leak");

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        try repl(allocator);
    } else if (args.len == 2) {
        try runFile(args[1]);
    } else {
        std.log.err("usage: zlox [path]", .{});
        std.process.exit(64);
    }
}

fn repl(allocator: std.mem.Allocator) !void {
    var read_buf: [1024]u8 = undefined;
    const stdin_file = std.fs.File.stdin();
    var stdin_reader = stdin_file.reader(&read_buf);
    const stdin = &stdin_reader.interface;

    const vm = try VM.init(allocator, stdout, stderr);
    defer vm.deinit();

    while (true) {
        try stdout.writeAll("> ");
        try stdout.flush();

        const input = stdin.takeDelimiterExclusive('\n') catch {
            stdout.writeByte('\n') catch {};
            stdout.flush() catch {};
            break;
        };

        const chunk = Compiler.compile(input, allocator, &vm.garbage_collector, stderr) catch |err| {
            stderr.print("invalid syntax: {}\n", .{err}) catch {};
            stderr.flush() catch {};
            continue;
        };
        defer chunk.deinit();

        vm.interpret(chunk) catch {};
    }
}

fn runFile(path: [:0]u8) !void {
    _ = path;
}

const std = @import("std");
const VM = @import("VM.zig");
const Compiler = @import("Compiler.zig");
