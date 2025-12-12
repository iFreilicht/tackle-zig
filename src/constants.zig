pub const board_size = 10;
pub const max_job_size = 8;

/// Column letters A-J
/// The lower case i is used for legibility and defined like this in the official Tackle rules.
pub const column_letters = [board_size]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'i', 'J' };

pub const block_sigil = "▢";
