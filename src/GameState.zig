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

const CommentWinning = tackle.notation.CommentWinning;
const SpecialAction = tackle.notation.SpecialAction;
const ColumnX = tackle.position.ColumnX;
const RowY = tackle.position.RowY;
const Position = tackle.position.Position;
const Move = tackle.Move;
const Turn = tackle.Turn;
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

/// Which color the next placed/moved piece must have
pub fn currentColor(self: GameState) PieceColor {
    return switch (self.currentPlayer()) {
        .white => .white,
        .black => if (self.phase == .place_gold) .gold else .black,
    };
}

const TurnEndEvent = enum {
    game_finished,
    // TODO: Add job_in_one and a detection algorithm to find out if there's just one move left.
    gold_removed,
};

/// End the players turn, updating the turn counter and phase
/// and executing special actions.
fn endTurn(self: *GameState) ?TurnEndEvent {
    var end_event: ?TurnEndEvent = null;
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
                return .game_finished;
            }
            if (self.board.hasGoldPiece() and self.board.isBorderEmpty()) {
                self.board.removeGoldPiece() catch unreachable;
                end_event = .gold_removed;
            }
            self.turn += 1;
        },
        .finished => unreachable,
    }
    return end_event;
}

/// Execute a turn, checking for the correct turn order and phase.
/// Returns the executed turn, which might contain additional information
/// about special actions or winning conditions!
pub fn executeTurn(self: *GameState, turn: Turn) !Turn {
    if (turn.color != self.currentColor()) return error.NotCurrentColorTurn;

    return switch (turn.action) {
        .place => |pos| try self.placeNextPiece(pos),
        .move => |move| try self.executeMove(move),
    };
}

/// Place a piece for the current player and end their turn,
/// checking for game rules.
/// Returns the executed turn.
pub fn placeNextPiece(self: *GameState, at: Position) !Turn {
    const color = switch (self.phase) {
        .opening => PieceColor.fromPlayer(self.currentPlayer()),
        .place_gold => .gold,
        .main, .finished => return error.InvalidPhase,
    };

    try self.board.executePlacement(color, at);

    _ = self.endTurn();

    return Turn{ .color = color, .action = .{ .place = at } };
}

/// Execute a move for the current player and end their turn,
/// checking for game rules and correct phase.
/// Returns the executed turn.
pub fn executeMove(self: *GameState, move: Move) !Turn {
    if (self.phase != .main) return error.InvalidPhase;

    const player = self.currentPlayer();
    const color = PieceColor.fromPlayer(player);

    const num_pieces_moved = try self.board.executeMove(player, move);

    const end_event = self.endTurn();

    const is_block_move = num_pieces_moved > 1;
    const winning: ?CommentWinning = if (end_event == .game_finished) .win else null;
    const special_action: ?SpecialAction = if (end_event == .gold_removed) .gold_removed else null;

    return Turn{
        .color = color,
        .action = .{ .move = move },
        .is_block_move = is_block_move,
        .winning = winning,
        .special_action = special_action,
    };
}

test "entire game works correctly and correct turns are returned" {
    var game_state = GameState.init(Job.turm3());

    const turn0 = try game_state.placeNextPiece(.{ .B, ._1 });
    const turn1 = try game_state.placeNextPiece(.{ .D, ._10 });
    // White places at A10
    const turn2 = try game_state.executeTurn(Turn{
        .color = .white,
        .action = .{ .place = .{ .A, ._10 } },
    });
    _ = try game_state.placeNextPiece(.{ .F, ._1 });
    _ = try game_state.placeNextPiece(.{ .C, ._10 });
    _ = try game_state.placeNextPiece(.{ .J, ._5 });
    _ = try game_state.placeNextPiece(.{ .A, ._8 });
    _ = try game_state.placeNextPiece(.{ .F, ._10 });
    _ = try game_state.placeNextPiece(.{ .G, ._10 });
    _ = try game_state.placeNextPiece(.{ .A, ._4 });
    // Color in turn is validated in executeTurn
    const turn9_part2_fail = game_state.executeTurn(Turn{
        .color = .black,
        .action = .{ .place = .{ .F, ._5 } },
    });
    try expectError(error.NotCurrentColorTurn, turn9_part2_fail);

    const turn9_part2 = try game_state.executeTurn(Turn{
        .color = .gold,
        .action = .{ .place = .{ .F, ._5 } },
    });

    const turn10 = try game_state.executeMove(.{ .vertical = .{ .x = .B, .from_y = ._1, .to_y = ._8 } });
    _ = try game_state.executeMove(.{ .horizontal = .{ .from_x = .D, .to_x = .E, .y = ._10 } });
    _ = try game_state.executeMove(.{ .horizontal = .{ .from_x = .A, .to_x = .I, .y = ._8 } });
    _ = try game_state.executeMove(.{ .horizontal = .{ .from_x = .E, .to_x = .H, .y = ._10 } });
    const turn14 = try game_state.executeTurn(.{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{ .from_x = .J, .to_x = .F, .y = ._8 } } },
    });
    _ = try game_state.executeMove(.{ .vertical = .{ .x = .I, .from_y = ._10, .to_y = ._5 } });
    _ = try game_state.executeMove(.{ .diagonal = .{ .from = .top_right, .distance = 2 } });
    const turn17 = try game_state.executeMove(.{ .horizontal = .{ .from_x = .J, .to_x = .I, .y = ._5 } });
    const final_turn = try game_state.executeMove(.{ .horizontal = .{ .from_x = .E, .to_x = .F, .y = ._8 } });

    try expectEqual(.finished, game_state.phase);
    try expectEqual(18, game_state.turn);

    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .place = .{ .B, ._1 } },
    }, turn0);

    try expectEqualDeep(Turn{
        .color = .black,
        .action = .{ .place = .{ .D, ._10 } },
    }, turn1);

    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .place = .{ .A, ._10 } },
    }, turn2);

    try expectEqualDeep(Turn{
        .color = .gold,
        .action = .{ .place = .{ .F, ._5 } },
    }, turn9_part2);

    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{ .x = .B, .from_y = ._1, .to_y = ._8 } } },
    }, turn10);

    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{ .from_x = .J, .to_x = .F, .y = ._8 } } },
        .is_block_move = true,
    }, turn14);

    try expectEqualDeep(Turn{
        .color = .black,
        .action = .{ .move = .{ .horizontal = .{ .from_x = .J, .to_x = .I, .y = ._5 } } },
        .is_block_move = true,
    }, turn17);

    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .move = .{ .horizontal = .{ .from_x = .E, .to_x = .F, .y = ._8 } } },
        .is_block_move = true,
        .winning = .win,
    }, final_turn);
}

test "gold piece is removed when appropriate" {
    var board = Board{};
    // Place 11 pieces at random, only two pieces should be on the border
    try board.placePiece(.white, .{ .B, ._10 });
    try board.placePiece(.black, .{ .J, ._1 });
    try board.placePiece(.white, .{ .B, ._4 });
    try board.placePiece(.black, .{ .E, ._6 });
    try board.placePiece(.white, .{ .F, ._3 });
    try board.placePiece(.black, .{ .H, ._4 });
    try board.placePiece(.white, .{ .C, ._7 });
    try board.placePiece(.black, .{ .D, ._8 });
    try board.placePiece(.white, .{ .G, ._2 });
    try board.placePiece(.black, .{ .I, ._9 });
    // Gold piece in the core, as usual
    try board.placePiece(.gold, .{ .F, ._5 });

    var game_state = GameState{
        .turn = 22,
        .phase = .main,
        .board = board,
        .job = Job.turm4(),
    };

    // Move white piece from border to court
    const turn23 = try game_state.executeMove(.{ .vertical = .{ .x = .B, .from_y = ._10, .to_y = ._5 } });
    // Move black piece from border to court, this should remove the gold piece
    const turn24 = try game_state.executeMove(.{ .diagonal = .{ .from = .bottom_right, .distance = 1 } });

    try expectEqual(false, game_state.board.hasGoldPiece());
    try expectEqualDeep(Turn{
        .color = .white,
        .action = .{ .move = .{ .vertical = .{ .x = .B, .from_y = ._10, .to_y = ._5 } } },
    }, turn23);
    try expectEqualDeep(Turn{
        .color = .black,
        .action = .{ .move = .{ .diagonal = .{ .from = .bottom_right, .distance = 1 } } },
        .special_action = .gold_removed,
    }, turn24);
}
