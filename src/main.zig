const std = @import("std");
const Btree = @import("bTree.zig").Btree;

pub const Record = struct { id: usize, name: []const u8, email: []const u8, address: []const u8 };

pub fn main() !void {
    var tree = try Btree(Record).init();
    defer tree.deinit();

    try tree.insert(.{ .id = 1, .name = "alice", .email = "alice@example.com", .address = "home" });
    try tree.insert(.{ .id = 2, .name = "bob", .email = "bob@example.com", .address = "home" });
    try tree.insert(.{ .id = 3, .name = "carol", .email = "carol@example.com", .address = "home" });
    try tree.insert(.{ .id = 4, .name = "dave", .email = "dave@example.com", .address = "home" });
    try tree.insert(.{ .id = 5, .name = "eve", .email = "eve@example.com", .address = "home" });
    try tree.insert(.{ .id = 6, .name = "frank", .email = "frank@example.com", .address = "office" });
    try tree.insert(.{ .id = 7, .name = "grace", .email = "grace@example.com", .address = "school" });
    try tree.insert(.{ .id = 8, .name = "heidi", .email = "heidi@example.com", .address = "university" });
    try tree.insert(.{ .id = 9, .name = "ivan", .email = "ivan@example.com", .address = "cafe" });
    try tree.insert(.{ .id = 10, .name = "judy", .email = "judy@example.com", .address = "library" });
    try tree.insert(.{ .id = 11, .name = "mallory", .email = "mallory@example.com", .address = "gym" });
    try tree.insert(.{ .id = 12, .name = "oscar", .email = "oscar@example.com", .address = "station" });
    try tree.insert(.{ .id = 13, .name = "peggy", .email = "peggy@example.com", .address = "market" });
    try tree.insert(.{ .id = 14, .name = "trent", .email = "trent@example.com", .address = "lab" });
    try tree.insert(.{ .id = 15, .name = "victor", .email = "victor@example.com", .address = "club" });
    try tree.insert(.{ .id = 16, .name = "wendy", .email = "wendy@example.com", .address = "cabin" });
    try tree.insert(.{ .id = 17, .name = "zara", .email = "zara@example.com", .address = "hostel" });
    try tree.insert(.{ .id = 18, .name = "yves", .email = "yves@example.com", .address = "apartment" });
    try tree.insert(.{ .id = 19, .name = "quinn", .email = "quinn@example.com", .address = "shed" });
    try tree.insert(.{ .id = 20, .name = "nina", .email = "nina@example.com", .address = "villa" });

    std.debug.print("Inserted records.\n", .{});
    try tree.traverseAllNodes();
    const dataList = try tree.traverse();
    for (dataList) |value| {
        std.debug.print("Id: {d}, Name: {s}, Email: {s} , Address:{s}\n", .{ value.id, value.name, value.email, value.address });
    }

    const result = try tree.search(5);
    if (result) |record| {
        std.debug.print(" Name: {s}, Email: {s} , Address:{s}\n", .{ record.name, record.email, record.address });
    } else {
        std.debug.print("Not found.\n", .{});
    }

    const deleted = try tree.delete(5);
    if (deleted) {
        std.debug.print("Deleted key 1 from internal node.\n", .{});
    } else {
        std.debug.print("Key 1 not deleted.\n", .{});
    }

    // //try tree.traverseAllNodes();

    std.debug.print("After deletion records.\n", .{});
    const newList = try tree.traverse();
    for (newList) |value| {
        std.debug.print("Id: {d}, Name: {s}, Email: {s} , Address:{s}\n", .{ value.id, value.name, value.email, value.address });
    }

    const new_result = try tree.search(5);
    if (new_result) |record| {
        std.debug.print(" Name: {s}, Email: {s} , Address:{s}\n", .{ record.name, record.email, record.address });
    } else {
        std.debug.print("Not found.\n", .{});
    }
}
