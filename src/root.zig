const std = @import("std");

pub const board = @import("board.zig");
pub const enums = @import("enums.zig");
pub const constants = @import("constants.zig");
pub const move = @import("move.zig");
pub const notation = @import("notation.zig");
pub const position = @import("position.zig");
pub const state = @import("state.zig");
pub const text_renderer = @import("text_renderer.zig");

const board_size = constants.board_size;
const max_job_size = constants.max_job_size;
const column_letters = constants.column_letters;

pub const Move = move.Move;
pub const GameState = state.GameState;
pub const Job = state.Job;
pub const TurnParser = notation.TurnParser;

pub fn place_demo_pieces(game_state: *GameState) !void {
    try game_state.place_next_piece(.{ .A, ._10 }); // White
    try game_state.place_next_piece(.{ .B, ._1 }); // Black
    try game_state.place_next_piece(.{ .J, ._9 }); // White
    try game_state.place_next_piece(.{ .E, ._1 }); // Black
    try game_state.place_next_piece(.{ .C, ._1 }); // White
    try game_state.place_next_piece(.{ .J, ._8 }); // Black
    try game_state.place_next_piece(.{ .J, ._6 }); // White
    try game_state.place_next_piece(.{ .E, ._10 }); // Black
    try game_state.place_next_piece(.{ .C, ._10 }); // White
    try game_state.place_next_piece(.{ .A, ._8 }); // Black
    try game_state.place_next_piece(.{ .D, ._5 }); // Gold
}

/// Interface for callbacks to user input and output.
/// Functions are currently forced to be known at compile time,
/// but we may want to use function pointers in the future for more flexibility.
pub const UserInterface = struct {
    /// Ask the user for the next move.
    get_next_move: fn () anyerror!Move,

    /// Render the current game state.
    render: fn (state: *const GameState) anyerror!void,
};

/// Runs the main game loop, deferring to `ui` for input and output.
pub fn run_game_loop(init_state: GameState, ui: UserInterface) !GameState {
    var game_state = init_state;

    while (game_state.phase != .finished) {
        ui.render(&game_state) catch |err| {
            std.debug.print("Error rendering game state: {}\n", .{err});
        };

        const turn_move = ui.get_next_move() catch |err| {
            // When simulating games, we might run out of moves, even if the
            // game is not finished yet. In that case, we just end the game.
            if (err == error.NoMoreMoves) {
                std.debug.print("No more moves in simulation. Ending game.\n", .{});
                break;
            }
            std.debug.print("Error getting next move: {}\n", .{err});
            continue;
        };

        game_state.execute_move(game_state.next_player(), turn_move) catch |err| {
            std.debug.print("Error executing move '{f}': {}\n", .{ turn_move, err });
            continue;
        };
    }

    return game_state;
}

fn SimulatedUserInterface(moves: []const Move) type {
    return struct {
        var moves_executed: usize = 0;

        const interface: UserInterface = .{
            .get_next_move = get_next_move,
            .render = render,
        };

        pub fn get_next_move() !Move {
            if (moves_executed >= moves.len) {
                return error.NoMoreMoves;
            }
            const next_move = moves[moves_executed];
            moves_executed += 1;
            return next_move;
        }

        pub fn render(_: *const GameState) !void {}
    };
}

test "game loop runs without errors" {
    var init_state = GameState.init(Job.turm3());

    try place_demo_pieces(&init_state);

    const moves = [_]Move{
        .{ .vertical = .{ .x = .C, .from_y = ._1, .to_y = ._6 } }, // White
        .{ .horizontal = .{ .from_x = .J, .y = ._8, .to_x = .D } }, // Black
        .{ .horizontal = .{ .from_x = .J, .y = ._6, .to_x = .D } }, // White
        .{ .vertical = .{ .x = .E, .from_y = ._10, .to_y = ._8 } }, // Black
        // This would be the winning move, but we don't check for win conditions yet
        .{ .diagonal = .{ .from = .top_left, .distance = 4 } }, // White
    };

    const mock_ui = SimulatedUserInterface(&moves);

    const final_state = try run_game_loop(init_state, mock_ui.interface);

    // This renders the final board state to stdout for visual feedback during testing.
    // It's not strictly necessary for the test itself, but I like it.
    const stdout = std.fs.File.stdout();
    var output_buffer: [50]u8 = undefined;
    var writer = stdout.writer(&output_buffer);
    try text_renderer.render_board(&writer.interface, &final_state.board);

    try board.expectBoardContent(
        &final_state.board,
        &.{ .{ .C, ._10 }, .{ .C, ._6 }, .{ .D, ._6 }, .{ .E, ._6 }, .{ .J, ._9 } },
        &.{ .{ .B, ._1 }, .{ .D, ._8 }, .{ .E, ._1 }, .{ .E, ._8 }, .{ .A, ._8 } },
        .{ .D, ._5 },
    );
}
