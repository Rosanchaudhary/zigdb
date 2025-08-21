
const std = @import("std");
const Btree = @import("bTree.zig").Btree;

pub const Record = struct { name: []const u8, email: []const u8, address: []const u8 };

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var tree = try Btree(Record).init(allocator);

    defer tree.deinit();

    try tree.insert(.{ .name = "alice", .email = "alice@example.com", .address = "home" });
    try tree.insert(.{ .name = "bob", .email = "bob@example.com", .address = "home" });
    try tree.insert(.{ .name = "carol", .email = "carol@example.com", .address = "home" });
    try tree.insert(.{ .name = "dave", .email = "dave@example.com", .address = "home" });
    try tree.insert(.{ .name = "eve", .email = "eve@example.com", .address = "home" });
    try tree.insert(.{ .name = "frank", .email = "frank@example.com", .address = "office" });
    try tree.insert(.{ .name = "grace", .email = "grace@example.com", .address = "school" });
    // try tree.insert(.{ .name = "heidi", .email = "heidi@example.com", .address = "university" });
    // try tree.insert(.{ .name = "ivan", .email = "ivan@example.com", .address = "cafe" });
    // try tree.insert(.{ .name = "judy", .email = "judy@example.com", .address = "library" });
    // try tree.insert(.{ .name = "mallory", .email = "mallory@example.com", .address = "gym" });
    // try tree.insert(.{ .name = "oscar", .email = "oscar@example.com", .address = "station" });
    // try tree.insert(.{ .name = "peggy", .email = "peggy@example.com", .address = "market" });
    // try tree.insert(.{ .name = "trent", .email = "trent@example.com", .address = "lab" });
    // try tree.insert(.{ .name = "victor", .email = "victor@example.com", .address = "club" });
    // try tree.insert(.{ .name = "wendy", .email = "wendy@example.com", .address = "cabin" });
    // try tree.insert(.{ .name = "zara", .email = "zara@example.com", .address = "hostel" });
    // try tree.insert(.{ .name = "yves", .email = "yves@example.com", .address = "apartment" });
    // try tree.insert(.{ .name = "quinn", .email = "quinn@example.com", .address = "shed" });
    // try tree.insert(.{ .name = "nina", .email = "nina@example.com", .address = "villa" });

    // std.debug.print("Inserted records.==============================\n", .{});
    // // try tree.traverseAllNodes();

    // _ = try tree.updateById(2, .{ .id = 2, .name = "bob marley do", .email = "nin@example.com", .address = "vill" });
    // _ = try tree.updateById(2, .{ .id = 2, .name = "hello", .email = "nin@example.com", .address = "vill" });

    const dataList = try tree.traverse();

    for (dataList) |value| {
        // ---- Print metadata ----
        std.debug.print("Record Metadata:\n", .{});
        std.debug.print("  id: {}\n", .{value.id});
        std.debug.print("  version: {}\n", .{value.version});
        std.debug.print("  created_at: {}\n", .{value.created_at});
        std.debug.print("  updated_at: {}\n", .{value.updated_at});
        std.debug.print("  previous_versions_offsets: ", .{});
        for (value.previous_versions_offsets) |off| {
            std.debug.print("{} ", .{off});
        }
        std.debug.print("\n", .{});
        std.debug.print("Printing record\n", .{});
        std.debug.print(" Id: {d}, Name: {s}, Email: {s} , Address:{s}\n", .{ value.id, value.data.name, value.data.email, value.data.address });
    }
}
