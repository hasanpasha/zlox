iter: ChunkIter,
stack: std.ArrayList(Value),
globals: std.AutoHashMap(*StringObject, Value),
allocator: std.mem.Allocator,
garbage_collector: GarbageCollector,
writer: *std.Io.Writer,
error_writer: *std.Io.Writer,

pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, error_writer: *std.Io.Writer) !*VM {
    const self = try allocator.create(VM);
    self.stack = try .initCapacity(allocator, 8);
    self.globals = .init(allocator);
    self.allocator = allocator;
    self.garbage_collector = .init(allocator);
    self.writer = writer;
    self.error_writer = error_writer;
    return self;
}

pub fn deinit(self: *VM) void {
    self.stack.deinit(self.allocator);
    self.globals.deinit();
    self.garbage_collector.deinit();
    self.allocator.destroy(self);
}

fn runtimeError(self: *VM, comptime fmt: []const u8, args: anytype) !void {
    try self.error_writer.print(fmt, args);

    const latest = self.iter.latest.?;
    const loc = latest.loc;
    try self.error_writer.print("[{f}] in script\n", .{loc});
    try self.error_writer.flush();
    self.stack.clearAndFree(self.allocator);
}

pub fn interpret(self: *VM, chunk: *Chunk) !void {
    self.iter = ChunkIter{ .chunk = chunk.* };
    try self.run();
}

pub const Error = error{
    runtime_error,
};

fn run(self: *VM) !void {
    defer self.writer.flush() catch {};

    while (try self.iter.next()) |op| {
        if (@import("config").trace) {
            try self.writer.print("{f}\t", .{op});
            for (self.stack.items) |value| {
                try self.writer.print("[{f}]", .{value});
            }
            try self.writer.writeByte('\n');
        }

        switch (op.op) {
            .constant => |val| try self.push(val),
            .nil => try self.push(.nil),
            .true => try self.push(.{ .bool = true }),
            .false => try self.push(.{ .bool = false }),
            .pop => _ = try self.pop(),
            .get_global => |name| {
                if (self.globals.get(name)) |value| {
                    try self.push(value);
                } else {
                    try self.runtimeError("undefined variable '{s}'.", .{name.data});
                }
            },
            .define_global => |name| {
                const value = try self.pop();
                try self.globals.put(name, value);
            },
            .set_global => |name| {
                if (self.globals.contains(name)) {
                    try self.globals.put(name, self.peek(0));
                } else {
                    try self.runtimeError("undefined variable '{s}'", .{name.data});
                }
            },
            .equal => {
                const b = try self.pop();
                const a = try self.pop();
                try self.push(.{ .bool = values_equal(a, b) });
            },
            .negate => {
                if (self.peek(0) != .number) {
                    try self.runtimeError("operand must be a number.", .{});
                    return Error.runtime_error;
                }
                try self.push(.{ .number = -(try self.pop()).number });
            },
            .greater, .less, .add, .subtract, .multiply, .divide => try self.binary_op(std.meta.activeTag(op.op)),
            .not => try self.push(.{ .bool = is_falsy(try self.pop()) }),
            .print => {
                const val = try self.pop();
                try self.writer.print("{f}\n", .{val});
            },
            .@"return" => return,
        }
    }
}

fn values_equal(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .nil => true,
        .bool => |val| val == b.bool,
        .number => |val| val == b.number,
        .object => |val| switch (val.kind) {
            .string => result: {
                const a_str = StringObject.case(val);
                const b_str = StringObject.case(b.object);
                break :result a_str == b_str;
            },
        },
    };
}

fn is_falsy(value: Value) bool {
    return switch (value) {
        .nil => true,
        .bool => |val| !val,
        else => false,
    };
}

fn binary_op(self: *VM, op: OpCode) !void {
    if (self.peek(0).isObjectType(.string) and self.peek(1).isObjectType(.string) and op == .add) {
        const b = StringObject.case((try self.pop()).object);
        const a = StringObject.case((try self.pop()).object);

        const new: [:0]u8 = try std.mem.concatWithSentinel(self.garbage_collector.allocator, u8, &.{ a.data, b.data }, 0);
        const result = try self.garbage_collector.takeString(new);
        try self.push(.{ .object = Object.castDown(result) });

        //
    } else if (self.peek(0) == .number and self.peek(1).isObjectType(.string) and op == .multiply) {
        const b = (try self.pop()).number;
        const a = StringObject.case((try self.pop()).object);
        const a_str = a.data;

        const times: usize = @intFromFloat(b);

        const length: usize = a_str.len * times;
        var str_buf: [:0]u8 = try self.garbage_collector.allocator.allocSentinel(u8, length, 0);

        for (0..times) |time| {
            const buffer_start = time * a_str.len;
            @memcpy(str_buf[buffer_start .. buffer_start + a_str.len], a_str);
        }

        const result = try self.garbage_collector.takeString(str_buf);
        try self.push(.{ .object = Object.castDown(result) });

        //
    } else if (self.peek(0) == .number or self.peek(1) == .number) {
        const b = (try self.pop()).number;
        const a = (try self.pop()).number;
        const val: Value = switch (op) {
            .greater => .{ .bool = a > b },
            .less => .{ .bool = a < b },
            .add => .{ .number = a + b },
            .subtract => .{ .number = a - b },
            .multiply => .{ .number = a * b },
            .divide => .{ .number = a / b },
            else => unreachable,
        };
        try self.push(val);
    } else {
        try self.runtimeError("Operands must be numbers or strings.", .{});
        return Error.runtime_error;
    }
}

fn push(self: *VM, value: Value) !void {
    try self.stack.append(self.allocator, value);
}

fn pop(self: *VM) !Value {
    return self.stack.pop() orelse error.stack_underflow;
}

fn peek(self: *VM, distance: usize) Value {
    return self.stack.items[self.stack.items.len - 1 - distance];
}

pub const ChunkIter = struct {
    index: usize = 0,
    latest: ?ExOp = null,
    chunk: Chunk,

    pub const ExOp = struct {
        op: Op,
        offset: usize,
        loc: Location,

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{:0>4} {f} {f}", .{ self.offset, self.loc, self.op });
        }
    };

    pub fn next(self: *ChunkIter) !?ExOp {
        if (self.index >= self.chunk.code.items.len)
            return null;

        const instruction = self.chunk.code.items[self.index];
        const opcode: OpCode = @enumFromInt(instruction);

        const exop = switch (opcode) {
            .constant => op: {
                const constant = self.chunk.code.items[self.index + 1];
                const val = self.chunk.constants.items[constant];

                break :op self.advance_with(2, .{ .constant = val });
            },
            .get_global, .define_global, .set_global => op: {
                const constant = self.chunk.code.items[self.index + 1];
                const name = StringObject.case(self.chunk.constants.items[constant].object);

                const this_op: Op = switch (opcode) {
                    .get_global => .{ .get_global = name },
                    .define_global => .{ .define_global = name },
                    .set_global => .{ .set_global = name },
                    else => unreachable,
                };

                break :op self.advance_with(2, this_op);
            },
            inline else => |tag| self.advance_with(1, @unionInit(Op, @tagName(tag), {})),
            _ => {
                self.index += 1;
                return error.unknown_opcode;
            },
        };

        self.latest = exop;
        return exop;
    }

    pub fn advance_with(self: *ChunkIter, offset: usize, op: Op) ExOp {
        const e = ExOp{
            .op = op,
            .offset = self.index,
            .loc = self.chunk.locations.items[self.index],
        };
        self.index += offset;
        return e;
    }
};

pub const Op = union(OpCode) {
    constant: Value,
    nil,
    true,
    false,
    pop,
    get_global: *StringObject,
    define_global: *StringObject,
    set_global: *StringObject,
    equal,
    greater,
    less,
    negate,
    add,
    subtract,
    multiply,
    divide,
    not,
    print,
    @"return",

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .constant => |val| try writer.print("constant {f}\t", .{val}),
            .get_global, .define_global, .set_global => |name| try writer.print("{f} \"{s}\"\t", .{
                std.meta.activeTag(self),
                name.data,
            }),
            inline else => |_, tag| try writer.print("{f}\t", .{tag}),
        }
    }
};

const VM = @This();
const std = @import("std");
const Value = @import("value.zig").Value;
const GarbageCollector = @import("GarbageCollector.zig");
const OpCode = @import("op_code.zig").OpCode;
const Chunk = @import("Chunk.zig");
const Object = @import("Object.zig");
const StringObject = Object.String;
const Location = @import("Location.zig");
