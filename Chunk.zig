code: std.ArrayList(u8),
constants: std.ArrayList(Value),
locations: std.ArrayList(Location),

allocator: std.mem.Allocator,

pub const Error = AllocError || error{overflow};

pub fn init(allocator: std.mem.Allocator) AllocError!*Chunk {
    const self = try allocator.create(Chunk);
    self.allocator = allocator;
    self.code = try .initCapacity(self.allocator, 8);
    self.constants = try .initCapacity(self.allocator, 8);
    self.locations = try .initCapacity(self.allocator, 8);

    return self;
}

pub fn deinit(self: *Chunk) void {
    self.code.deinit(self.allocator);
    self.constants.deinit(self.allocator);
    self.locations.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn write_op(self: *Chunk, op_code: OpCode, loc: Location) AllocError!void {
    try self.locations.append(self.allocator, loc);
    try self.code.append(self.allocator, @intFromEnum(op_code));
}

pub fn write(self: *Chunk, byte: u8, loc: Location) AllocError!void {
    try self.locations.append(self.allocator, loc);
    try self.code.append(self.allocator, byte);
}

pub fn write_constant(self: *Chunk, value: Value, loc: Location) Error!void {
    const constant = try self.add_constant(value);
    try self.write_op(.constant, loc);
    try self.write(constant, loc);
}

pub fn add_constant(self: *Chunk, value: Value) Error!u8 {
    if (self.constants.items.len + 1 >= 0xFF)
        return error.overflow;

    try self.constants.append(self.allocator, value);
    return @truncate(self.constants.items.len - 1);
}

const std = @import("std");
const AllocError = std.mem.Allocator.Error;
const Chunk = @This();
const Value = @import("value.zig").Value;
const Location = @import("Location.zig");
const OpCode = @import("op_code.zig").OpCode;
