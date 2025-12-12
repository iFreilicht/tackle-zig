const std = @import("std");
const constants = @import("constants.zig");
const board_size = constants.board_size;
const max_job_size = constants.max_job_size;
const column_letters = constants.column_letters;

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

const Position = enum { start, end, other };
const EvenOdd = enum { even, odd };

const margin = 4;
const margin_fmt = "{:3} ";
const row_height = 2;
const col_width = 4;
const last_i = board_size * row_height + 1;
const last_j = board_size * col_width + 1;

fn position(i: usize, last: comptime_int) Position {
    return switch (i) {
        0 => .start,
        last - 1 => .end,
        else => .other,
    };
}
fn iszero(i: usize) bool {
    return i == 0;
}

pub fn render_board(writer: *std.io.Writer) !void {
    var row_number: u8 = board_size;

    for (0..last_i) |i| {
        const i_pos = position(i, last_i);
        const i_on_line = i % row_height == 0;

        // Write left margin
        if (i_on_line) {
            _ = try writer.write(" " ** margin);
        } else {
            _ = try writer.print(margin_fmt, .{row_number});
            row_number -= 1;
        }

        for (0..last_j) |j| {
            const j_pos = position(j, last_j);
            const j_on_line = j % col_width == 0;

            const glyph = switch (i_pos) {
                .start => switch (j_pos) {
                    .start => corner_tl,
                    .end => corner_tr,
                    .other => if (j_on_line) xing_top else line_hori,
                },
                .end => switch (j_pos) {
                    .start => corner_bl,
                    .end => corner_br,
                    .other => if (j_on_line) xing_bott else line_hori,
                },
                .other => if (i_on_line)
                    switch (j_pos) {
                        .start => xing_left,
                        .end => xing_right,
                        .other => if (j_on_line) xing_center else line_hori,
                    }
                else if (j_on_line) line_vert else " ",
            };
            _ = try writer.write(glyph);
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
    try render_board(&writer);

    try std.testing.expectEqualSlices(u8, &buffer, expected);
}
