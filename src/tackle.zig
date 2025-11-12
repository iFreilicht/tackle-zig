const std = @import("std");

const board_size = 10;
const column_letters = [board_size]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'i', 'J' };

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
const row_height = 2;
const col_width = 4;
const last_i = board_size * row_height + 1;
const last_j = board_size * col_width + 1;
const buff_size = (last_j + margin) * 4;
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

pub fn board() !void {
    var row_number: u8 = board_size;
    for (0..last_i) |i| {
        var buffer = [1]u8{0} ** buff_size;
        var fbs = std.io.fixedBufferStream(&buffer);
        var writer = fbs.writer();

        const i_pos = position(i, last_i);
        const i_on_line = i % row_height == 0;

        // Write left margin
        if (i_on_line) {
            _ = try writer.write(" " ** margin);
        } else {
            _ = try writer.print("{:3} ", .{row_number});
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
        std.debug.print("{s}", .{buffer});
    }

    var col_number: u8 = 0;
    var buffer = [1]u8{0} ** buff_size;
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();
    for (0..margin + last_j) |j| {
        if (j > margin and (j - margin + (col_width / 2)) % col_width == 0) {
            _ = try writer.writeByte(column_letters[col_number]);
            col_number += 1;
        } else {
            _ = try writer.writeByte(' ');
        }
    }
    std.debug.print("{s}\n", .{buffer});
}
