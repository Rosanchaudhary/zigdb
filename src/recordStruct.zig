const std = @import("std");

pub fn RecordMetadata(comptime T:type) type {
    return struct {
        const Self = @This();
        /// Primary key or unique document ID
        id: usize,

        /// Incremented each time the record is updated
        version: u32,

        /// File offsets of older versions of this record in the record file
        previous_versions_offsets: []u64,

        /// Unix timestamp in seconds for when record was created
        created_at: i64,

        /// Unix timestamp in seconds for last update
        updated_at: i64,

        /// Whether the record is marked as deleted
        deleted: bool,

        /// Actual record data
        data: T,

        /// Helper function to create a new metadata record
        pub fn init(id: usize, record: T, allocator: std.mem.Allocator) !Self {
            const now = std.time.timestamp();
            return Self{
                .id = id,
                .version = 1,
                .previous_versions_offsets = try allocator.alloc(u64, 0), // empty initially
                .created_at = now,
                .updated_at = now,
                .deleted = false,
                .data = record,
            };
        }

        /// Helper function to create a new metadata record
        pub fn update(id: usize, record: T, previous_offsets: []u64, created_at: i64) !Self {
            const now = std.time.timestamp();
            return Self{
                .id = id,
                .version = @intCast(previous_offsets.len + 1),
                .previous_versions_offsets = previous_offsets,
                .created_at = created_at,
                .updated_at = now,
                .deleted = false,
                .data = record,
            };
        }
    };
}
