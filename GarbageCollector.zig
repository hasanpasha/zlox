allocator: std.mem.Allocator,
objects: ?*Object = null,
strings: std.StringHashMap(*StringObject),

pub fn init(allocator: std.mem.Allocator) ObjectAllocator {
    return .{
        .allocator = allocator,
        .strings = .init(allocator),
    };
}

pub fn deinit(self: *ObjectAllocator) void {
    self.freeObjects();
    self.strings.deinit();
}

pub fn allocateObject(self: *ObjectAllocator, comptime T: type, kind: ObjectKind) !*T {
    const object_child = try self.allocator.create(T);
    const object: *Object = .castDown(object_child);
    object.kind = kind;

    object.next = self.objects;
    self.objects = object;

    return object_child;
}

pub fn takeString(self: *ObjectAllocator, string: [:0]const u8) !*StringObject {
    if (self.strings.get(string)) |obj| {
        self.allocator.free(string);
        return obj;
    }

    return self.allocateStirng(string);
}

pub fn copyString(self: *ObjectAllocator, string: []const u8) !*StringObject {
    if (self.strings.get(string)) |obj|
        return obj;

    const heap_chars = try self.allocator.dupeZ(u8, string);
    return self.allocateStirng(heap_chars);
}

pub fn allocateStirng(self: *ObjectAllocator, heap_string: [:0]const u8) !*StringObject {
    const string_obj = try self.allocateObject(StringObject, .string);
    string_obj.data = heap_string;

    try self.strings.put(heap_string, string_obj);

    return string_obj;
}

pub fn freeObject(self: ObjectAllocator, object: *Object) void {
    switch (object.kind) {
        .string => {
            const string = StringObject.case(object);
            self.allocator.free(string.data);
            self.allocator.destroy(string);
        },
    }
}

pub fn freeObjects(self: *ObjectAllocator) void {
    while (self.objects) |object| {
        const next = object.next;
        self.freeObject(object);
        self.objects = next;
    }
}

const std = @import("std");
const ObjectAllocator = @This();
const Object = @import("Object.zig");
const ObjectKind = Object.Kind;
const StringObject = Object.String;
