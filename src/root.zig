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
pub const Action = notation.Action;
pub const Turn = notation.Turn;
pub const Player = enums.Player;
pub const PieceColor = enums.PieceColor;
pub const Phase = GameState.Phase;
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

    const datafile = try DataFile.load(allocator, &reader) orelse unreachable;

    for (datafile.turns.items) |turn| {
        // We ignore the returned Turn here, there's no reason to modify the DataFile during setup.
        _ = try game_state.executeTurn(turn);
    }
}

/// Interface for callbacks to user input and output.
/// Functions are currently forced to be known at compile time,
/// but we may want to use function pointers in the future for more flexibility.
/// TODO: Make this an intrusive interface like io.Writer
pub const UserInterface = struct {
    /// Writer to write log messages to
    log_writer: *std.io.Writer,

    /// Ask the user to take the next action (piece placement or move)
    getNextAction: fn (player: Player, phase: Phase) anyerror!Action,

    /// Record a turn taken by a player, for example to a `DataFile`.
    /// It is important that an implementation only records turns when this callback is called.
    /// Recording turns in `getNextPlacement` or `getNextMove` would be premature, as the action
    /// might not be valid according to the game rules and thus not actually taken.
    record: ?fn (record_args: RecordArgs, turn: Turn) anyerror!void = null,

    /// Render the current game state.
    render: ?fn (state: GameState) anyerror!void = null,
};

pub const RecordArgs = struct {
    /// The allocator to use for any dynamic memory allocations in the DataFile.
    gpa: std.mem.Allocator,
    /// Pointer to the DataFile to record turns into.
    datafile_ptr: *DataFile,
    /// Pointer to the open file the DataFile is being saved to.
    file_ptr: *std.fs.File,
};

/// Runs the main game loop, deferring to `ui` for input and output.
pub fn runGameLoop(init_state: GameState, ui: UserInterface, record_args: ?RecordArgs) !GameState {
    if (ui.record != null and record_args == null) {
        return error.RecordArgsRequired;
    }

    var game_state = init_state;

    while (game_state.phase != .finished) {
        if (ui.render) |render| {
            render(game_state) catch |err| {
                try ui.log_writer.print("Error rendering game state: {}\n", .{err});
            };
        }

        const player = game_state.currentPlayer();

        const action = ui.getNextAction(player, game_state.phase) catch |err| {
            // When simulating games, we might run out of actions, even if the
            // game is not finished yet. In that case, we just end the game.
            if (err == error.NoMoreActions) {
                try ui.log_writer.print("No more actions in simulation. Ending game.\n", .{});
                break;
            }
            try ui.log_writer.print("Error getting next action: {}\n", .{err});
            continue;
        };

        const color = game_state.currentColor();
        const input_turn = Turn{ .color = color, .action = action };

        const executed_turn = game_state.executeTurn(input_turn) catch |err| {
            try ui.log_writer.print("Error executing action '{f}': {}\n", .{ action, err });
            continue;
        };
        if (ui.record) |record| {
            record(
                record_args orelse unreachable,
                executed_turn,
            ) catch |err| {
                try ui.log_writer.print("Error recording turn '{f}': {}\n", .{ input_turn, err });
            };
        }
    }

    if (ui.render) |render| {
        render(game_state) catch |err| {
            try ui.log_writer.print("Error rendering game state: {}\n", .{err});
        };
    }

    return game_state;
}

test "game loop runs without errors" {
    const init_state = GameState.init(Job.turm3());

    const actions = [_]Action{
        .{ .place = .{ .A, ._10 } }, // White
        .{ .place = .{ .B, ._1 } }, // Black
        .{ .place = .{ .J, ._9 } }, // White
        .{ .place = .{ .E, ._1 } }, // Black
        .{ .place = .{ .C, ._1 } }, // White
        .{ .place = .{ .J, ._8 } }, // Black
        .{ .place = .{ .J, ._6 } }, // White
        .{ .place = .{ .E, ._10 } }, // Black
        .{ .place = .{ .C, ._10 } }, // White
        .{ .place = .{ .A, ._8 } }, // Black
        .{ .place = .{ .D, ._5 } }, // Gold
        .{ .move = .{
            .vertical = .{ .x = .C, .from_y = ._1, .to_y = ._6 },
        } }, // White
        .{ .move = .{
            .horizontal = .{ .from_x = .J, .y = ._8, .to_x = .D },
        } }, // Black
        .{ .move = .{
            .horizontal = .{ .from_x = .J, .y = ._6, .to_x = .D },
        } }, // White
        .{ .move = .{
            .vertical = .{ .x = .E, .from_y = ._10, .to_y = ._8 },
        } }, // Black
        .{ .move = .{
            .diagonal = .{ .from = .top_left, .distance = 4 },
        } }, // White
    };

    const mock_ui = testing.simulatedUserInterface(&actions);

    const final_state = try runGameLoop(init_state, mock_ui, null);

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
