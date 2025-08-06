const std = @import("std");

const Person = struct {
    name: []const u8,
    age: u8,
};

pub fn main() void {
    const T = Person;
    const info = @typeInfo(T).Struct;

    inline for (info.fields) |field| {
        std.debug.print("Field: {s}\n", .{field.name});
    }
}
