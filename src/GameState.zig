const GameState = @This();
const std = @import("std");

const tackle = @import("root.zig");

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualSlices = std.testing.expectEqualSlices;

const Board = tackle.Board;
const Job = tackle.Job;

const Player = tackle.enums.Player;
const PieceColor = tackle.enums.PieceColor;
const SquareContent = tackle.enums.SquareContent;

const ColumnX = tackle.position.ColumnX;
const RowY = tackle.position.RowY;
const Position = tackle.position.Position;
const Move = tackle.Move;
const BlockSize = tackle.position.BlockSize;
const Direction = tackle.enums.Direction;
const movePosition = tackle.position.movePosition;
const movePositionIfPossible = tackle.position.movePositionIfPossible;
const posFromInt = tackle.position.posFromInt;

/// Turn count, starting with zero
turn: u32,
phase: Phase,
board: Board,
job: Job,

pub const Phase = enum(u2) {
    /// Initial phase where pieces are placed on the board
    opening,
    /// Zero-turn phase after black's last piece has been placed,
    /// in which they place the gold piece in the core
    place_gold,
    main,
    finished,
};

pub fn init(job: Job) GameState {
    return GameState{
        .turn = 0,
        .phase = .opening,
        .board = .{},
        .job = job,
    };
}

/// Which player's turn it is
pub fn currentPlayer(self: GameState) Player {
    return if (self.turn % 2 == 0) .white else .black;
}

fn endTurn(self: *GameState) void {
    switch (self.phase) {
        .opening => {
            if (self.turn == self.job.piecesPerPlayer() * 2 - 1) {
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
            const finished = self.job.isFulfilled(self.board, self.currentPlayer());
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
pub fn placeNextPiece(self: *GameState, at: Position) !void {
    switch (self.phase) {
        .opening => {
            const color = PieceColor.fromPlayer(self.currentPlayer());
            try self.board.executePlacement(color, at);
        },
        .place_gold => {
            try self.board.executePlacement(.gold, at);
        },
        .main, .finished => return error.InvalidPhase,
    }

    self.endTurn();
}

/// Execute a move for the specified player, checking for turn order and phase validity.
pub fn executeMove(self: *GameState, move: Move) !void {
    if (self.phase != .main) return error.InvalidPhase;

    try self.board.executeMove(self.currentPlayer(), move);

    self.endTurn();
}
