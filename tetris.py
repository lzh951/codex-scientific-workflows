"""Terminal-based Tetris game implemented with curses.

Controls:
    Left/Right arrows or A/D to move
    Up arrow or W to rotate
    Down arrow or S to soft drop
    Space to hard drop
    P to pause, Q to quit

Run with: `python tetris.py`
"""
from __future__ import annotations

import curses
import random
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple

BOARD_WIDTH = 10
BOARD_HEIGHT = 20
PREVIEW_ROWS = 6
TICK_RATE = 0.05  # seconds between input polls

Shape = List[Tuple[int, int]]
Rotations = List[Shape]

TETROMINOES: Dict[str, Rotations] = {
    "I": [
        [(0, 1), (1, 1), (2, 1), (3, 1)],
        [(2, 0), (2, 1), (2, 2), (2, 3)],
    ],
    "J": [
        [(0, 0), (0, 1), (1, 1), (2, 1)],
        [(1, 0), (2, 0), (1, 1), (1, 2)],
        [(0, 1), (1, 1), (2, 1), (2, 2)],
        [(1, 0), (1, 1), (0, 2), (1, 2)],
    ],
    "L": [
        [(2, 0), (0, 1), (1, 1), (2, 1)],
        [(1, 0), (1, 1), (1, 2), (2, 2)],
        [(0, 1), (1, 1), (2, 1), (0, 2)],
        [(0, 0), (1, 0), (1, 1), (1, 2)],
    ],
    "O": [
        [(1, 0), (2, 0), (1, 1), (2, 1)],
    ],
    "S": [
        [(1, 0), (2, 0), (0, 1), (1, 1)],
        [(1, 0), (1, 1), (2, 1), (2, 2)],
    ],
    "T": [
        [(1, 0), (0, 1), (1, 1), (2, 1)],
        [(1, 0), (1, 1), (2, 1), (1, 2)],
        [(0, 1), (1, 1), (2, 1), (1, 2)],
        [(1, 0), (0, 1), (1, 1), (1, 2)],
    ],
    "Z": [
        [(0, 0), (1, 0), (1, 1), (2, 1)],
        [(2, 0), (1, 1), (2, 1), (1, 2)],
    ],
}

COLORS = {
    "I": curses.COLOR_CYAN,
    "J": curses.COLOR_BLUE,
    "L": curses.COLOR_YELLOW,
    "O": curses.COLOR_MAGENTA,
    "S": curses.COLOR_GREEN,
    "T": curses.COLOR_WHITE,
    "Z": curses.COLOR_RED,
}


def rotate(shape: Rotations, rotation: int) -> Shape:
    return shape[rotation % len(shape)]


@dataclass
class Piece:
    kind: str
    rotation: int
    x: int
    y: int

    @property
    def blocks(self) -> Shape:
        return rotate(TETROMINOES[self.kind], self.rotation)


def create_board() -> List[List[str]]:
    return [[" "] * BOARD_WIDTH for _ in range(BOARD_HEIGHT)]


def can_move(board: List[List[str]], piece: Piece, dx: int, dy: int, drot: int = 0) -> bool:
    new_rotation = (piece.rotation + drot) % len(TETROMINOES[piece.kind])
    new_blocks = rotate(TETROMINOES[piece.kind], new_rotation)
    for bx, by in new_blocks:
        nx = piece.x + bx + dx
        ny = piece.y + by + dy
        if nx < 0 or nx >= BOARD_WIDTH or ny < 0 or ny >= BOARD_HEIGHT:
            return False
        if board[ny][nx] != " ":
            return False
    return True


def lock_piece(board: List[List[str]], piece: Piece) -> None:
    for bx, by in piece.blocks:
        nx = piece.x + bx
        ny = piece.y + by
        if 0 <= ny < BOARD_HEIGHT:
            board[ny][nx] = piece.kind


def clear_lines(board: List[List[str]]) -> int:
    new_board = [row for row in board if any(cell == " " for cell in row)]
    cleared = BOARD_HEIGHT - len(new_board)
    for _ in range(cleared):
        new_board.insert(0, [" "] * BOARD_WIDTH)
    board[:] = new_board
    return cleared


def new_piece() -> Piece:
    kind = random.choice(list(TETROMINOES.keys()))
    rotation = 0
    x = BOARD_WIDTH // 2 - 2
    y = 0
    return Piece(kind, rotation, x, y)


def draw_border(window: curses.window, top: int, left: int, height: int, width: int) -> None:
    window.attron(curses.A_DIM)
    for row in range(height + 2):
        window.addch(top + row, left, "│")
        window.addch(top + row, left + width + 1, "│")
    for col in range(width + 2):
        window.addch(top, left + col, "─")
        window.addch(top + height + 1, left + col, "─")
    window.addch(top, left, "┌")
    window.addch(top, left + width + 1, "┐")
    window.addch(top + height + 1, left, "└")
    window.addch(top + height + 1, left + width + 1, "┘")
    window.attroff(curses.A_DIM)


def draw_board(window: curses.window, board: List[List[str]], piece: Piece | None) -> None:
    for y, row in enumerate(board):
        for x, cell in enumerate(row):
            draw_cell(window, x, y, cell)
    if piece:
        for bx, by in piece.blocks:
            draw_cell(window, piece.x + bx, piece.y + by, piece.kind, ghost=False)


def draw_cell(window: curses.window, x: int, y: int, cell: str, ghost: bool = False) -> None:
    char = "█" if cell != " " else " "
    if cell == " ":
        window.addstr(y + 1, x * 2 + 1, "  ")
        return

    color_pair = curses.color_pair(ord(cell)) if curses.has_colors() else 0
    if ghost:
        window.attron(curses.A_DIM)
    if color_pair:
        window.attron(color_pair)
    window.addstr(y + 1, x * 2 + 1, char * 2)
    if color_pair:
        window.attroff(color_pair)
    if ghost:
        window.attroff(curses.A_DIM)


def draw_ghost(window: curses.window, board: List[List[str]], piece: Piece) -> None:
    ghost_piece = Piece(piece.kind, piece.rotation, piece.x, piece.y)
    while can_move(board, ghost_piece, 0, 1):
        ghost_piece.y += 1
    for bx, by in ghost_piece.blocks:
        draw_cell(window, ghost_piece.x + bx, ghost_piece.y + by, ghost_piece.kind, ghost=True)


def setup_colors() -> None:
    if not curses.has_colors():
        return
    curses.start_color()
    for kind, color in COLORS.items():
        curses.init_pair(ord(kind), color, curses.COLOR_BLACK)


def display_info(window: curses.window, score: int, level: int, lines: int, next_piece: Piece) -> None:
    info_top = 2
    info_left = BOARD_WIDTH * 2 + 4
    window.addstr(info_top, info_left, "Score: {:>6}".format(score))
    window.addstr(info_top + 1, info_left, "Level: {:>6}".format(level))
    window.addstr(info_top + 2, info_left, "Lines: {:>6}".format(lines))
    window.addstr(info_top + 4, info_left, "Next:")

    for row in range(PREVIEW_ROWS):
        window.addstr(info_top + 5 + row, info_left, " " * 12)

    for bx, by in rotate(TETROMINOES[next_piece.kind], next_piece.rotation):
        px = info_left + 2 + bx * 2
        py = info_top + 6 + by
        if curses.has_colors():
            window.attron(curses.color_pair(ord(next_piece.kind)))
        window.addstr(py, px, "██")
        if curses.has_colors():
            window.attroff(curses.color_pair(ord(next_piece.kind)))

    window.addstr(info_top + PREVIEW_ROWS + 7, info_left, "Controls:")
    controls = [
        "←/A: Left",
        "→/D: Right",
        "↓/S: Soft drop",
        "↑/W: Rotate",
        "Space: Hard drop",
        "P: Pause",
        "Q: Quit",
    ]
    for i, text in enumerate(controls, start=info_top + PREVIEW_ROWS + 8):
        window.addstr(i, info_left, text.ljust(18))


def game_over(window: curses.window, score: int) -> None:
    msg = "Game Over! Score: {}".format(score)
    window.addstr(BOARD_HEIGHT // 2, 2, msg)
    window.addstr(BOARD_HEIGHT // 2 + 2, 2, "Press Q to quit or R to restart")
    window.nodelay(False)
    while True:
        key = window.getch()
        if key in (ord("q"), ord("Q")):
            raise SystemExit
        if key in (ord("r"), ord("R")):
            return


def soft_drop(board: List[List[str]], piece: Piece) -> bool:
    if can_move(board, piece, 0, 1):
        piece.y += 1
        return True
    return False


def hard_drop(board: List[List[str]], piece: Piece) -> None:
    while can_move(board, piece, 0, 1):
        piece.y += 1


def update_level(score: int, lines_cleared: int) -> Tuple[int, float]:
    level = lines_cleared // 10 + 1
    gravity = max(0.1, 1.0 - (level - 1) * 0.1)
    return level, gravity


def play(stdscr: curses.window) -> None:
    curses.curs_set(0)
    stdscr.nodelay(True)
    stdscr.timeout(int(TICK_RATE * 1000))
    setup_colors()

    board = create_board()
    current = new_piece()
    next_piece = new_piece()
    score = 0
    lines_cleared = 0
    level, gravity = update_level(score, lines_cleared)
    last_drop = time.time()
    paused = False

    while True:
        stdscr.erase()
        draw_border(stdscr, 0, 0, BOARD_HEIGHT, BOARD_WIDTH * 2)
        draw_board(stdscr, board, current)
        draw_ghost(stdscr, board, current)
        display_info(stdscr, score, level, lines_cleared, next_piece)
        stdscr.refresh()

        try:
            key = stdscr.getch()
        except curses.error:
            key = -1

        if key in (ord("q"), ord("Q")):
            break
        if key in (ord("p"), ord("P")):
            paused = not paused
        if paused:
            stdscr.addstr(BOARD_HEIGHT // 2, BOARD_WIDTH - 3, "Paused")
            stdscr.refresh()
            time.sleep(TICK_RATE)
            continue

        if key in (curses.KEY_LEFT, ord("a"), ord("A")) and can_move(board, current, -1, 0):
            current.x -= 1
        elif key in (curses.KEY_RIGHT, ord("d"), ord("D")) and can_move(board, current, 1, 0):
            current.x += 1
        elif key in (curses.KEY_DOWN, ord("s"), ord("S")):
            if soft_drop(board, current):
                score += 1
        elif key in (curses.KEY_UP, ord("w"), ord("W")) and can_move(board, current, 0, 0, 1):
            current.rotation = (current.rotation + 1) % len(TETROMINOES[current.kind])
        elif key == ord(" "):
            hard_drop(board, current)

        if time.time() - last_drop >= gravity:
            if not soft_drop(board, current):
                lock_piece(board, current)
                cleared = clear_lines(board)
                if cleared:
                    lines_cleared += cleared
                    score += (cleared ** 2) * 100
                    level, gravity = update_level(score, lines_cleared)
                current = next_piece
                next_piece = new_piece()
                if not can_move(board, current, 0, 0):
                    game_over(stdscr, score)
                    board = create_board()
                    current = new_piece()
                    next_piece = new_piece()
                    score = 0
                    lines_cleared = 0
                    level, gravity = update_level(score, lines_cleared)
            last_drop = time.time()

        time.sleep(TICK_RATE)


def main() -> None:
    curses.wrapper(play)


if __name__ == "__main__":
    main()
