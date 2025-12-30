const std = @import("std");
const constants = @import("constants.zig");
const board_module = @import("board.zig");
const enums = @import("enums.zig");
const job_module = @import("job.zig");
const position = @import("position.zig");
const move_module = @import("move.zig");

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualSlices = std.testing.expectEqualSlices;

const max_job_size = constants.max_job_size;

const Board = board_module.Board;
const Job = job_module.Job;

const Player = enums.Player;
const PieceColor = enums.PieceColor;
const SquareContent = enums.SquareContent;

const ColumnX = position.ColumnX;
const RowY = position.RowY;
const Position = position.Position;
const Move = move_module.Move;
const BlockSize = position.BlockSize;
const Direction = enums.Direction;
const is_on_border = position.is_on_border;
const is_in_core = position.is_in_core;
const move_position = position.move_position;
const move_position_if_possible = position.move_position_if_possible;
const pos_from_int = position.pos_from_int;

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

    pub fn init(job: Job) GameState {
        return GameState{
            .turn = 0,
            .phase = .opening,
            .board = .{},
            .job = job,
        };
    }

    /// Which player's turn it is
    pub fn current_player(self: *const GameState) Player {
        return if (self.turn % 2 == 0) .white else .black;
    }

    pub fn pieces_per_player(self: *const GameState) u4 {
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
                const finished = self.job.is_fulfilled(&self.board, self.current_player());
                if (finished) {
                    self.phase = .finished;
                    return;
                }
                self.turn += 1;
            },
            .finished => unreachable,
        }
    }

    /// Place a piece for the current player and end their turn,
    /// checking for game rules.
    pub fn place_next_piece(self: *GameState, at: Position) !void {
        switch (self.phase) {
            .opening => {
                if (!is_on_border(at)) return error.PieceNotOnBorder;
                const color: PieceColor = switch (self.current_player()) {
                    .white => .white,
                    .black => .black,
                };
                try self.board.place_piece(color, at);
            },
            .place_gold => {
                if (!is_in_core(at)) return error.GoldNotInCore;
                try self.board.place_piece(.gold, at);
            },
            .main => return error.InvalidPhase,
            .finished => return error.InvalidPhase,
        }

        self.end_turn();
    }

    /// Execute a move for the specified player, checking for turn order and phase validity.
    pub fn execute_move(self: *GameState, player: Player, move: Move) !void {
        if (player != self.current_player()) return error.NotYourTurn;
        if (self.phase != .main) return error.InvalidPhase;

        try self.board.execute_move(player, move);

        self.end_turn();
    }
};
