const std = @import("std");
const Btree = @import("bTree.zig").Btree;

const Record = struct { name: []const u8, email: []const u8 };

pub fn main() void {
    var tree = Btree(Record).init();
    defer tree.deinit();

    tree.insertRecord(.{ .name = "alice", .email = "alice@example.com" });
    tree.insertRecord(.{ .name = "bob", .email = "bob@example.com" });
    tree.insertRecord(.{ .name = "carol", .email = "carol@example.com" });
    tree.insertRecord(.{ .name = "dave", .email = "dave@example.com" });
    tree.insertRecord(.{ .name = "eve", .email = "eve@example.com" });
    tree.insertRecord(.{ .name = "frank", .email = "frank@example.com" });
    tree.insertRecord(.{ .name = "grace", .email = "grace@example.com" });
    tree.insertRecord(.{ .name = "heidi", .email = "heidi@example.com" });
    tree.insertRecord(.{ .name = "ivan", .email = "ivan@example.com" });
    tree.insertRecord(.{ .name = "judy", .email = "judy@example.com" });

    std.debug.print("BTree contents (sorted order):\n", .{});
    tree.traverse();

    if (tree.searchTree(2)) |record| {
        std.debug.print("Found: name:{s},email:{s}\n", .{ record.name, record.email });
    } else {
        std.debug.print("Not found.\n", .{});
    }
    std.debug.print("\nAfter deleting 1:\n", .{});
    tree.remove(1);
    if (tree.searchTree(1)) |record| {
        std.debug.print("Found:name:{s},email:{s}\n", .{ record.name, record.email });
    } else {
        std.debug.print("Not found.\n", .{});
    }
    std.debug.print("\nAfter deleting 1:\n", .{});
    std.debug.print("BTree contents (sorted order):\n", .{});
    tree.traverse();
}
