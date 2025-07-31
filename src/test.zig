const std = @import("std");
const testing = std.testing;

const Record = struct {
    name: []const u8,
    email: []const u8,
};

const Btree = @import("bTree.zig").Btree;

test "insert and search records in BTree" {
    var tree = Btree(Record).init();
    defer tree.deinit();

    tree.insertRecord(.{ .name = "alice", .email = "alice@example.com" });
    tree.insertRecord(.{ .name = "bob", .email = "bob@example.com" });

    try testing.expect(tree.searchTree(0) != null);
    try testing.expectEqualStrings("alice", tree.searchTree(0).?.name);
    try testing.expectEqualStrings("bob", tree.searchTree(1).?.name);
}

test "search non-existent record" {
    var tree = Btree(Record).init();
    defer tree.deinit();

    tree.insertRecord(.{ .name = "alice", .email = "alice@example.com" });

    const result = tree.searchTree(99);
    try testing.expect(result == null);
}

test "delete record and search again" {
    var tree = Btree(Record).init();
    defer tree.deinit();

    tree.insertRecord(.{ .name = "carol", .email = "carol@example.com" });

    try testing.expect(tree.searchTree(0) != null);
    tree.remove(0);
    try testing.expect(tree.searchTree(0) == null);
}

test "multiple insertions and traversals" {
    var tree = Btree(Record).init();
    defer tree.deinit();

    tree.insertRecord(.{ .name = "dave", .email = "dave@example.com" });
    tree.insertRecord(.{ .name = "eve", .email = "eve@example.com" });
    tree.insertRecord(.{ .name = "frank", .email = "frank@example.com" });

    // This just checks if traverse works without crashing.
    // Consider adding a way to collect values in an array for full testability.
    tree.traverse();

    try testing.expect(tree.searchTree(2) != null);
    try testing.expectEqualStrings("frank", tree.searchTree(2).?.name);
}
