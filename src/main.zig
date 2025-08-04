// main.zig
const std = @import("std");
const Btree = @import("bTree.zig").Btree;

const Record = struct {
    name: []const u8,
    email: []const u8,
};

pub fn main() !void {
    var tree = try Btree(Record).init();
    defer tree.deinit();

    try tree.insertRecord(.{ .name = "alice", .email = "alice@example.com" });
    try tree.insertRecord(.{ .name = "bob", .email = "bob@example.com" });
    try tree.insertRecord(.{ .name = "carol", .email = "carol@example.com" });
    try tree.insertRecord(.{ .name = "dave", .email = "dave@example.com" });
    // try tree.insertRecord(.{ .name = "eve", .email = "eve@example.com" });

    std.debug.print("Inserted records.\n", .{});
    try tree.traverse();
}
