const std = @import("std");
const expect = std.testing.expect;
const Btree = @import("bTree.zig").Btree;

pub const Record = struct {
    id: usize,
    name: []const u8,
    email: []const u8,
    address: []const u8,
};

test "insert, search and delete records from Btree" {
    var tree = try Btree(Record).init();
    defer tree.deinit();

    // Insert records
    try tree.insert(.{ .id = 1, .name = "alice", .email = "alice@example.com", .address = "home" });
    try tree.insert(.{ .id = 2, .name = "bob", .email = "bob@example.com", .address = "home" });
    try tree.insert(.{ .id = 3, .name = "carol", .email = "carol@example.com", .address = "home" });

    // Search existing record
    const found1 = try tree.search(1);
    std.debug.print("Record found {s}\n", .{found1.?.name});
    try expect(found1 != null);
    try expect(std.mem.eql(u8, found1.?.name, "alice"));
    try expect(std.mem.eql(u8, found1.?.email, "alice@example.com"));
    try expect(std.mem.eql(u8, found1.?.address, "home"));

    // Search non-existing record
    const not_found = try tree.search(999);
    try expect(not_found == null);

    // Delete existing record
    const deleted = try tree.delete(1);
    try expect(deleted);

    // Ensure deleted record is gone
    const should_be_null = try tree.search(1);
    try expect(should_be_null == null);

    // Delete another record
    const deleted2 = try tree.delete(2);
    try expect(deleted2);

    // Final deletion
    const deleted3 = try tree.delete(3);
    try expect(deleted3);

    // Ensure all records are deleted
    try expect((try tree.search(2)) == null);
    try expect((try tree.search(3)) == null);
}
