pub const Ti = 2;
pub const MAX_KEYS = 2 * Ti - 1;
pub const MAX_CHILDREN = MAX_KEYS + 1;
pub const MIN_KEYS = Ti - 1;

pub const node_serialized_size =
    1 + // is_leaf
    1 + // num_keys
    MAX_KEYS * @sizeOf(usize) +
    MAX_KEYS * @sizeOf(u64) +
    MAX_CHILDREN * @sizeOf(u64);

