const std = @import("std");
const tackle = @import("tackle.zig");
const text_renderer = tackle.text_renderer;

pub fn main() !void {
    // Initialize the board and place some pieces
    var board = tackle.board.Board{};
    try board.place_piece(.white, .{ .A, ._10 });
    try board.place_piece(.black, .{ .D, ._1 });

    // Parse and execute a couple of moves
    var input = std.io.Reader.fixed("wA10-C8");
    const turn = try tackle.notation.TurnParser.parse(&input);
    try board.execute_move(turn.by, turn.move);

    input = std.io.Reader.fixed("bD1-D7x");
    const turn2 = try tackle.notation.TurnParser.parse(&input);
    try board.execute_move(turn2.by, turn2.move);

    // Finally, render the board to stdout
    const stdout = std.fs.File.stdout();
    var buffer: [50]u8 = undefined;
    var writer = stdout.writer(&buffer);
    try text_renderer.render_board(&writer.interface, &board);
}

test "main runs without errors" {
    try main();
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
