const std = @import("std");

pub const Block = @import("Block.zig");
pub const Board = @import("Board.zig");
pub const DataFile = @import("DataFile.zig");
pub const enums = @import("enums.zig");
pub const constants = @import("constants.zig");
pub const Job = @import("Job.zig");
pub const move = @import("move.zig");
pub const notation = @import("notation.zig");
pub const position = @import("position.zig");
pub const GameState = @import("GameState.zig");
pub const TextRenderer = @import("TextRenderer.zig");
pub const testing = @import("testing.zig");
pub const text_ui = @import("text_ui.zig");

pub const Position = position.Position;
pub const Move = move.Move;
pub const Turn = notation.Turn;
pub const parsePosition = notation.parsePosition;
pub const parseTurn = notation.parseTurn;

/// Place some demo pieces on the board to speed up testing.
pub fn placeDemoPieces(game_state: *GameState) !void {
    // This number of bytes should be enough for the setup file.
    // The test will fail with OOM if it isn't.
    const num_bytes = 4096;
    const datafile_content = @embedFile("test_data/setup.txt");

    var datafile_buffer: [num_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&datafile_buffer);
    const allocator = fba.allocator();

    var reader = std.io.Reader.fixed(datafile_content);

    const datafile = try DataFile.load(allocator, &reader);

    for (datafile.placements.items) |placement| {
        try game_state.placeNextPiece(placement);
    }
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
                // When simulating games, we might run out of placements, even if the
                // game is not finished yet. In that case, we just end the game.
                if (err == error.NoMorePlacements) {
                    std.debug.print("No more placements in simulation. Ending game.\n", .{});
                    break;
                }
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

    const mock_ui = testing.simulatedUserInterface(&placements, &moves);

    const final_state = try runGameLoop(init_state, mock_ui);

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

test placeDemoPieces {
    var state = GameState.init(Job.turm3());

    try placeDemoPieces(&state);

    try std.testing.expectEqual(.white, state.board.getSquare(.{ .A, ._10 }));
    try std.testing.expectEqual(.black, state.board.getSquare(.{ .B, ._1 }));
    // Don't test all pieces, the content of setup.txt may change.
}
