const std = @import("std");
const tackle = @import("root.zig");
const text_renderer = tackle.text_renderer;

pub fn main() !void {
    const ui = struct {
        const stdin = std.fs.File.stdin();
        var input_buffer: [100]u8 = undefined;
        var reader = stdin.readerStreaming(&input_buffer);

        const stdout = std.fs.File.stdout();
        var output_buffer: [50]u8 = undefined;
        var writer = stdout.writer(&output_buffer);

        fn get_next_move() !tackle.Move {
            while (true) {
                std.debug.print("Enter your move:\n", .{});
                var slice: ?[]const u8 = null;
                while (slice == null) {
                    slice = try reader.interface.takeDelimiter('\n');
                }
                var move_reader = std.io.Reader.fixed(slice orelse unreachable);
                const turn = tackle.TurnParser.parse(&move_reader) catch |err| {
                    std.debug.print("Error parsing move: {}\n", .{err});
                    std.debug.print("Please enter a valid move:\n", .{});
                    continue;
                };
                return turn.move;
            }
        }

        fn render(state: *const tackle.GameState) !void {
            std.debug.print("\n\n", .{});
            try text_renderer.render_board(&writer.interface, &state.board);
            std.debug.print("{t} to move.\n", .{state.next_player()});
        }
    };

    const job = tackle.Job.turm3();
    var state = tackle.GameState.init(job);

    try tackle.place_demo_pieces(&state);

    try ui.render(&state);

    _ = try tackle.run_game_loop(state, ui.get_next_move, ui.render);
}

test {
    std.testing.refAllDecls(@This());
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
