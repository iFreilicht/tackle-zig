const std = @import("std");
const constants = @import("constants.zig");
const board_module = @import("board.zig");
const enums = @import("enums.zig");
const notation = @import("notation.zig");

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualSlices = std.testing.expectEqualSlices;

const max_job_size = constants.max_job_size;

const Board = board_module.Board;

const Player = enums.Player;
const PieceColor = enums.PieceColor;
const SquareContent = enums.SquareContent;

const ColumnX = notation.ColumnX;
const RowY = notation.RowY;
const Position = notation.Position;
const Move = notation.Move;
const BlockSize = notation.BlockSize;
const Direction = notation.Direction;
const move_position = notation.move_position;
const move_position_if_possible = notation.move_position_if_possible;

pub const JobRequirement = enum { piece, empty, any };
pub const Job = struct {
    size_x: u3,
    size_y: u3,
    requirements: [max_job_size * max_job_size]JobRequirement,
    total_pieces: u4, // Maximum of 16 pieces, see also `max_pieces_per_player`
};

pub const Phase = enum(u2) {
    /// Initial phase where pieces are placed on the board
    opening,
    /// Zero-turn phase after black's last piece has been placed,
    /// in which they place the gold piece in the core
    place_gold,
    main,
    finished,
};

pub const GameState = struct {
    /// Turn count, starting with zero
    turn: u32,
    phase: Phase,
    board: Board,
    job: Job,

    fn init(job: Job) GameState {
        return GameState{
            .next_player = .white,
            .board = Board,
            .job = job,
        };
    }

    fn next_player(self: *const GameState) Player {
        return if (self.turn % 2 == 0) .white else .black;
    }

    fn pieces_per_player(self: *const GameState) u4 {
        return self.job.total_pieces + 2;
    }

    fn end_turn(self: *GameState) void {
        switch (self.phase) {
            .opening => {
                if (self.turn == self.pieces_per_player() * 2 - 1) {
                    self.phase = .place_gold;
                    // Placing the gold piece is part of black's last turn during
                    // the opening, so DON'T increment the turn number here!
                } else {
                    self.turn += 1;
                }
            },
            .place_gold => {
                self.phase = .main;
                self.turn += 1;
            },
            .main => {
                self.turn += 1;
                // TODO: Check for win condition
            },
            .finished => unreachable,
        }
    }

    /// Place a piece for the current player and end their turn.
    /// Only allows placing pieces in the border, according to game rules.
    pub fn place_next_piece(self: *GameState, position: Position) !void {
        switch (self.phase) {
            .opening => {
                if (!notation.is_on_border(position)) return error.PieceNotOnBorder;
                try self.board.place_piece(self.next_player(), position);
            },
            .place_gold => {
                if (!notation.is_in_core(position)) return error.GoldNotInCore;
                try self.board.place_piece(.gold, position);
            },
            .main => return error.InvalidPhase,
            .finished => return error.InvalidPhase,
        }

        self.end_turn();
    }
};
