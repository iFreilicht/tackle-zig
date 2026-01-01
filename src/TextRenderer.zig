const std = @import("std");

const tackle = @import("root.zig");

const board_size = tackle.constants.board_size;
const max_job_size = tackle.constants.max_job_size;
const column_letters = tackle.constants.column_letters;

const Board = tackle.Board;
const RowY = tackle.position.RowY;
const ColumnX = tackle.position.ColumnX;
const Position = tackle.position.Position;

const corner_tl: []const u8 = "╭";
const corner_bl: []const u8 = "╰";
const corner_tr: []const u8 = "╮";
const corner_br: []const u8 = "╯";
const line_hori: []const u8 = "─";
const line_vert: []const u8 = "│";
const xing_top: []const u8 = "┬";
const xing_bott: []const u8 = "┴";
const xing_left: []const u8 = "├";
const xing_right: []const u8 = "┤";
const xing_center: []const u8 = "┼";

const RenderPosition = enum { start, end, on_line, on_symbol, other };
const EvenOdd = enum { even, odd };

const margin = 4;
const margin_fmt = "{:3} ";
const row_height = 2;
const col_width = 4;
const last_i = board_size * row_height + 1;
const last_j = board_size * col_width + 1;

fn renderPosition(i: usize, last: comptime_int, grid_size: comptime_int) RenderPosition {
    if (i == 0) {
        return .start;
    } else if (i == last - 1) {
        return .end;
    } else if (i % grid_size == 0) {
        return .on_line;
    } else if (i % grid_size == grid_size / 2) {
        return .on_symbol;
    } else {
        return .other;
    }
}
fn position(i: usize, j: usize) Position {
    const col: ColumnX = @enumFromInt((j / col_width) + 1);
    const row: RowY = @enumFromInt(10 - (i / row_height));
    return .{ col, row };
}

pub fn renderBoard(writer: *std.io.Writer, board: Board) !void {
    var row_number: u8 = board_size;

    for (0..last_i) |i| {
        const i_pos = renderPosition(i, last_i, row_height);

        // Write left margin
        switch (i_pos) {
            .on_symbol => {
                try writer.print(margin_fmt, .{row_number});
                row_number -= 1;
            },
            else => _ = try writer.write(" " ** margin),
        }

        for (0..last_j) |j| {
            const j_pos = renderPosition(j, last_j, col_width);

            const glyph = switch (i_pos) {
                .start => switch (j_pos) {
                    .start => corner_tl,
                    .end => corner_tr,
                    .on_line => xing_top,
                    else => line_hori,
                },
                .end => switch (j_pos) {
                    .start => corner_bl,
                    .end => corner_br,
                    .on_line => xing_bott,
                    else => line_hori,
                },
                .on_line => switch (j_pos) {
                    .start => xing_left,
                    .end => xing_right,
                    .on_line => xing_center,
                    else => line_hori,
                },
                .on_symbol => switch (j_pos) {
                    .start, .end, .on_line => line_vert,
                    .on_symbol => switch (board.getSquare(position(i, j))) {
                        .empty => " ",
                        .white => "□",
                        .black => "■",
                        .gold => "G",
                    },
                    .other => " ",
                },
                .other => " ",
            };
            _ = try writer.write(glyph);
            try writer.flush();
        }

        _ = try writer.write("\n");
    }

    var col_number: u8 = 0;
    for (0..margin + last_j) |j| {
        if (j > margin and (j - margin + (col_width / 2)) % col_width == 0) {
            _ = try writer.writeByte(column_letters[col_number]);
            col_number += 1;
        } else {
            _ = try writer.writeByte(' ');
        }
    }

    _ = try writer.write("\n");
    try writer.flush();
}

pub fn debugPrintBoard(board: Board) !void {
    const stdout = std.fs.File.stdout();
    var output_buffer: [50]u8 = undefined;
    var writer = stdout.writer(&output_buffer);
    try renderBoard(&writer.interface, board);
}

test "empty board is drawn correctly" {
    const expected =
        \\    ╭───┬───┬───┬───┬───┬───┬───┬───┬───┬───╮
        \\ 10 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  9 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  8 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  7 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  6 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  5 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  4 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  3 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  2 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  1 │   │   │   │   │   │   │   │   │   │   │
        \\    ╰───┴───┴───┴───┴───┴───┴───┴───┴───┴───╯
        \\      A   B   C   D   E   F   G   H   i   J  
        \\
    ;

    var buffer: [2134:0]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    try renderBoard(&writer, .{});

    try std.testing.expectEqualSlices(u8, &buffer, expected);
}

test "board with a few pieces is drawn correctly" {
    const expected =
        \\    ╭───┬───┬───┬───┬───┬───┬───┬───┬───┬───╮
        \\ 10 │ □ │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  9 │   │   │ ■ │   │   │   │ □ │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  8 │   │   │ □ │   │   │   │ ■ │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  7 │   │   │   │ G │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  6 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  5 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  4 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  3 │   │   │   │   │   │   │   │   │   │ □ │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  2 │   │   │   │   │   │   │   │   │   │   │
        \\    ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
        \\  1 │   │   │   │   │ □ │   │   │   │   │ ■ │
        \\    ╰───┴───┴───┴───┴───┴───┴───┴───┴───┴───╯
        \\      A   B   C   D   E   F   G   H   i   J  
        \\
    ;

    var board: Board = .{};
    try board.placePiece(.white, .{ .A, ._10 });
    try board.placePiece(.black, .{ .C, ._9 });
    try board.placePiece(.white, .{ .G, ._9 });
    try board.placePiece(.white, .{ .C, ._8 });
    try board.placePiece(.black, .{ .G, ._8 });
    try board.placePiece(.gold, .{ .D, ._7 });
    try board.placePiece(.white, .{ .J, ._3 });
    try board.placePiece(.white, .{ .E, ._1 });
    try board.placePiece(.black, .{ .J, ._1 });
    var buffer: [2150:0]u8 = undefined;
    var writer = std.io.Writer.fixed(&buffer);
    try renderBoard(&writer, board);
    try std.testing.expectEqualStrings(&buffer, expected);
}
