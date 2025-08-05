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
    try tree.insertRecord(.{ .name = "eve", .email = "eve@example.com" });
    try tree.insertRecord(.{ .name = "frank", .email = "frank@example.com" });
    try tree.insertRecord(.{ .name = "grace", .email = "grace@example.com" });
    try tree.insertRecord(.{ .name = "heidi", .email = "heidi@example.com" });
    try tree.insertRecord(.{ .name = "ivan", .email = "ivan@example.com" });
    try tree.insertRecord(.{ .name = "judy", .email = "judy@example.com" });
    try tree.insertRecord(.{ .name = "mallory", .email = "mallory@example.com" });
    try tree.insertRecord(.{ .name = "nathan", .email = "nathan@example.com" });
    try tree.insertRecord(.{ .name = "olivia", .email = "olivia@example.com" });
    try tree.insertRecord(.{ .name = "peggy", .email = "peggy@example.com" });
    try tree.insertRecord(.{ .name = "quentin", .email = "quentin@example.com" });
    try tree.insertRecord(.{ .name = "ruth", .email = "ruth@example.com" });
    try tree.insertRecord(.{ .name = "sybil", .email = "sybil@example.com" });
    try tree.insertRecord(.{ .name = "trent", .email = "trent@example.com" });
    try tree.insertRecord(.{ .name = "ursula", .email = "ursula@example.com" });
    try tree.insertRecord(.{ .name = "victor", .email = "victor@example.com" });

    std.debug.print("Inserted records.\n", .{});
    try tree.traverse();
    //try tree.traverseAllNodes();
}
