const std = @import("std");

pub const Block = @import("Block.zig");
pub const Board = @import("Board.zig");
pub const enums = @import("enums.zig");
pub const constants = @import("constants.zig");
pub const Job = @import("Job.zig");
pub const move = @import("move.zig");
pub const notation = @import("notation.zig");
pub const position = @import("position.zig");
pub const GameState = @import("GameState.zig");
pub const TextRenderer = @import("TextRenderer.zig");

pub const Position = position.Position;
pub const Move = move.Move;
pub const parsePosition = notation.parsePosition;
pub const parseTurn = notation.parseTurn;

/// Place some demo pieces on the board to speed up testing.
pub fn placeDemoPieces(game_state: *GameState) !void {
    try game_state.placeNextPiece(.{ .A, ._10 }); // White
    try game_state.placeNextPiece(.{ .B, ._1 }); // Black
    try game_state.placeNextPiece(.{ .J, ._9 }); // White
    try game_state.placeNextPiece(.{ .E, ._1 }); // Black
    try game_state.placeNextPiece(.{ .C, ._1 }); // White
    try game_state.placeNextPiece(.{ .J, ._8 }); // Black
    try game_state.placeNextPiece(.{ .J, ._6 }); // White
    try game_state.placeNextPiece(.{ .E, ._10 }); // Black
    // I want to test placing pieces as well, so leaving these commented out for now.
    //try game_state.placeNextPiece(.{ .C, ._10 }); // White
    //try game_state.placeNextPiece(.{ .A, ._8 }); // Black
    //try game_state.placeNextPiece(.{ .D, ._5 }); // Gold
}

/// Interface for callbacks to user input and output.
/// Functions are currently forced to be known at compile time,
/// but we may want to use function pointers in the future for more flexibility.
pub const UserInterface = struct {
    /// Ask the user where the next piece should be placed.
    getNextPlacement: fn () anyerror!Position,

    /// Ask the user for the next move.
    getNextMove: fn (state: GameState) anyerror!Move,

    /// Render the current game state.
    render: fn (state: GameState) anyerror!void,
};

/// Runs the main game loop, deferring to `ui` for input and output.
pub fn runGameLoop(init_state: GameState, ui: UserInterface) !GameState {
    var game_state = init_state;

    while (game_state.phase != .finished) {
        ui.render(game_state) catch |err| {
            std.debug.print("Error rendering game state: {}\n", .{err});
        };

        if (game_state.phase == .opening or game_state.phase == .place_gold) {
            const placement = ui.getNextPlacement() catch |err| {
                std.debug.print("Error getting next placement: {}\n", .{err});
                continue;
            };

            const x, const y = placement;
            game_state.placeNextPiece(placement) catch |err| {
                std.debug.print("Error placing piece at '{f}{f}': {}\n", .{ x, y, err });
                continue;
            };
            continue;
        }

        const turn_move = ui.getNextMove(game_state) catch |err| {
            // When simulating games, we might run out of moves, even if the
            // game is not finished yet. In that case, we just end the game.
            if (err == error.NoMoreMoves) {
                std.debug.print("No more moves in simulation. Ending game.\n", .{});
                break;
            }
            std.debug.print("Error getting next move: {}\n", .{err});
            continue;
        };

        game_state.executeMove(game_state.currentPlayer(), turn_move) catch |err| {
            std.debug.print("Error executing move '{f}': {}\n", .{ turn_move, err });
            continue;
        };
    }

    ui.render(game_state) catch |err| {
        std.debug.print("Error rendering game state: {}\n", .{err});
    };

    return game_state;
}

fn SimulatedUserInterface(placements: []const Position, moves: []const Move) type {
    return struct {
        var pieces_placed: usize = 0;
        var moves_executed: usize = 0;

        const interface: UserInterface = .{
            .getNextPlacement = getNextPlacement,
            .getNextMove = getNextMove,
            .render = render,
        };

        pub fn getNextPlacement() anyerror!Position {
            const next_placement = placements[pieces_placed];
            pieces_placed += 1;
            return next_placement;
        }

        pub fn getNextMove(_: GameState) !Move {
            if (moves_executed >= moves.len) {
                return error.NoMoreMoves;
            }
            const next_move = moves[moves_executed];
            moves_executed += 1;
            return next_move;
        }

        pub fn render(_: GameState) !void {}
    };
}

test "game loop runs without errors" {
    const init_state = GameState.init(Job.turm3());

    const placements = [_]Position{
        .{ .A, ._10 }, // White
        .{ .B, ._1 }, // Black
        .{ .J, ._9 }, // White
        .{ .E, ._1 }, // Black
        .{ .C, ._1 }, // White
        .{ .J, ._8 }, // Black
        .{ .J, ._6 }, // White
        .{ .E, ._10 }, // Black
        .{ .C, ._10 }, // White
        .{ .A, ._8 }, // Black
        .{ .D, ._5 }, // Gold
    };

    const moves = [_]Move{
        .{ .vertical = .{ .x = .C, .from_y = ._1, .to_y = ._6 } }, // White
        .{ .horizontal = .{ .from_x = .J, .y = ._8, .to_x = .D } }, // Black
        .{ .horizontal = .{ .from_x = .J, .y = ._6, .to_x = .D } }, // White
        .{ .vertical = .{ .x = .E, .from_y = ._10, .to_y = ._8 } }, // Black
        .{ .diagonal = .{ .from = .top_left, .distance = 4 } }, // White
    };

    const mock_ui = SimulatedUserInterface(&placements, &moves);

    const final_state = try runGameLoop(init_state, mock_ui.interface);

    // This renders the final board state to stdout for visual feedback during testing.
    // It's not strictly necessary for the test itself, but I like it.
    try TextRenderer.debugPrintBoard(final_state.board);

    try final_state.board.expectContent(
        &.{ .{ .C, ._10 }, .{ .C, ._6 }, .{ .D, ._6 }, .{ .E, ._6 }, .{ .J, ._9 } },
        &.{ .{ .B, ._1 }, .{ .D, ._8 }, .{ .E, ._1 }, .{ .E, ._8 }, .{ .A, ._8 } },
        .{ .D, ._5 },
    );

    try std.testing.expectEqual(final_state.phase, .finished);
    try std.testing.expectEqual(final_state.turn, 14);
}
