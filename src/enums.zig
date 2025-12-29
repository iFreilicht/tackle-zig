/// Cardinal directions on the board
pub const Direction = enum(u2) {
    /// Along column, increasing row
    up,
    /// Along column, decreasing row
    down,
    /// Along row, decreasing column
    left,
    /// Along row, increasing column
    right,
};

/// Player colors
pub const Player = enum(u2) { white = 1, black = 2 };

/// Piece colors. Equivalent to Player, but with additional 'gold' color.
/// The gold piece is placed by the black player but can't be moved.
pub const PieceColor = enum(u2) { white = 1, black = 2, gold = 3 };

/// Content of a square on the board. Equivalent to PieceColor, but with additional 'empty' value.
pub const SquareContent = enum(u2) {
    empty = 0,
    white = 1,
    black = 2,
    gold = 3,

    pub fn from_player(p: Player) @This() {
        return @enumFromInt(@intFromEnum(p));
    }

    pub fn from_color(c: PieceColor) @This() {
        return @enumFromInt(@intFromEnum(c));
    }
};

/// Validate that the piece being moved belongs to the player
pub fn validate_color(player: Player, color: SquareContent) !void {
    switch (player) {
        .white => if (color != .white) return error.IllegalMove,
        .black => if (color != .black) return error.IllegalMove,
    }
}
