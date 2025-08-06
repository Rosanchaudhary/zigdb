const std = @import("std");
const Btree = @import("bTree.zig").Btree;

pub const Record = struct { name: []const u8, email: []const u8, address: []const u8 };

pub fn main() !void {
    var tree = try Btree(Record).init();
    defer tree.deinit();

    try tree.insertRecord(.{ .name = "alice", .email = "alice@example.com", .address = "home" });
    try tree.insertRecord(.{ .name = "bob", .email = "bob@example.com", .address = "home" });
    try tree.insertRecord(.{ .name = "carol", .email = "carol@example.com", .address = "home" });
    try tree.insertRecord(.{ .name = "dave", .email = "dave@example.com", .address = "home" });
    try tree.insertRecord(.{ .name = "eve", .email = "eve@example.com", .address = "home" });

    std.debug.print("Inserted records.\n", .{});
    const dataList = try tree.traverse();
    for (dataList) |value| {
        std.debug.print(" Name: {s}, Email: {s} , Address:{s}\n", .{ value.name, value.email, value.address });
    }
}
