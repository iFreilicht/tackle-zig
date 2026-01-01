/// The board is always 10x10
pub const board_edge_length = 10;
pub const board_size = board_edge_length * board_edge_length;

/// All player pieces have to start on the border. So the absolute maximum
/// number of pieces per player is 18. In practice, this could allow sitations
/// to occur where a player can no longer place any piece on the border (because
/// you can't place pieces adjacent to your own). With that in mind, the actual
/// maximum number of pieces per player is 12. This guarantees that all pieces
/// can be placed. The rules say the "most difficult" job is block9,
/// which requires 11 pieces per player, but custom jobs could consist of 10
/// pieces.
pub const max_pieces_per_player = 12;

/// Maximum number of pieces in a job. See above
pub const max_pieces_in_job = 10;

/// For a job to be completed, no piece can be on the border.
/// Thus the absolute maximum edge length of a job is 8x8.
pub const max_job_edge_length = board_edge_length - 2;

/// Maximum number of squares in a job's area.
/// We could define max_job_size as max_job_edge_length * max_job_edge_length,
/// but that's not a realistic job size at all and takes up 64 bytes for any
/// job's requirements array, even though most jobs are much smaller.
/// The largest official job is treppe5 with an area of 5x5 = 25.
/// A lower size is likelier to yield good cache locality, and it's unlikely
/// that anyone will try to define a custom job larger than 8x3, 6x4 or 5x5,
/// (especially as a job can only consist of 10 pieces maximum) so we pick 25
/// as a reasonable compromise.
pub const max_job_size = 25;

/// Column letters A-J
/// The lower case i is used for legibility and defined like this in the official Tackle rules.
pub const column_letters = [board_edge_length]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'i', 'J' };

pub const block_sigil = "▢";
