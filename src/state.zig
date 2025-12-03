const constants = @import("constants.zig");
const board_size = constants.board_size;
const max_job_size = constants.max_job_size;

pub const Player = enum { white, black };
pub const PieceColor = enum { white, black, gold };
pub const JobRequirement = enum { piece, empty, any };

pub const GameState = struct {
    next: Player,
    board: [board_size][board_size]?PieceColor,
    job: [max_job_size][max_job_size]JobRequirement,
};
