/// The board is always 10x10
pub const board_size = 10;

/// For a job to be completed, no piece can be on the border.
/// Thus the absolute maximum job size is 8x8.
pub const max_job_size = 8;

/// All player pieces have to start on the border. So the maximum
/// number of pieces per player is 18. In practice, this would require a 16 piece
/// job like block4, which is impractical but technically playable.
pub const max_pieces_per_player = 18;

/// Column letters A-J
/// The lower case i is used for legibility and defined like this in the official Tackle rules.
pub const column_letters = [board_size]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'i', 'J' };

pub const block_sigil = "▢";
