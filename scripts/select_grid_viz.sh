#!/usr/bin/env bash
# select_grid_viz.sh — Live progress visualiser for `pkdx select --progress=json`.
#
# Reads JSON Lines on stdin (one event per line) and renders progress in one
# of two modes:
#
# - **TTY mode** (stdout is a terminal): draws a fixed grid of cells, updates
#   the cell at (row, col) on each `cell_start` event, and tags it as done
#   when the next cell_start arrives or the phase ends. Phases are colour-
#   coded so screening fill (cyan) and dp-refine fill (magenta) remain
#   distinguishable. The current in-progress cell is rendered as `o` in
#   yellow, completed cells as `#`. ASCII glyphs are used deliberately:
#   East Asian / CJK locales render box-drawing characters (▢ / ■ / ·) as
#   width 2, which breaks the column alignment of the 60×60 grid because
#   the cursor-move (`paint`) is column-indexed under width-1 assumption.
# - **Non-TTY mode** (stdout is a pipe / file / Claude Code Bash output):
#   prints one line per phase boundary plus a final "phase done (N cells)"
#   summary, so log-style consumers (CI, agents) get useful output without
#   thousands of escape sequences.
#
# Usage:
#   cat input.json \
#     | bin/pkdx select --progress=json 2> >(scripts/select_grid_viz.sh) \
#     > result.json
#
# Env:
#   ROWS / COLS    — grid dims (default 60×60, matches 6v6 single)
#   FORCE_MODE     — "tty" / "plain" to override auto-detection (rare)

set -u

ROWS=${ROWS:-60}
COLS=${COLS:-60}

if [ "${FORCE_MODE:-}" = "tty" ] || { [ "${FORCE_MODE:-}" != "plain" ] && [ -t 1 ]; }; then
  MODE=tty
else
  MODE=plain
fi

if [ "$MODE" = tty ]; then
  # Hide cursor while drawing; restore + park below grid on exit.
  cleanup() { printf '\033[?25h\033[%d;1H\n' "$((ROWS + 4))"; }
  trap cleanup EXIT INT TERM
  printf '\033[?25l'

  awk -v ROWS="$ROWS" -v COLS="$COLS" '
  BEGIN {
    printf "\033[2J\033[H"
    printf "Phase: (waiting)\n\n"
    for (r = 0; r < ROWS; r++) {
      for (c = 0; c < COLS; c++) printf "\033[2m.\033[0m"
      printf "\n"
    }
    fflush()
    prev_row = -1; prev_col = -1
    current_phase = ""
  }

  function get_phase(line,    _) {
    if (match(line, /"phase":"[^"]+"/) > 0) {
      return substr(line, RSTART + 9, RLENGTH - 10)
    }
    return "?"
  }

  # Coloured "done" mark for cells that completed under each phase.
  # `o` (in-progress) is replaced by `#` (filled), colour-coded per phase so
  # screening fill (cyan) and dp-refine fill (magenta) remain distinguishable.
  # Glyphs are ASCII (width 1 on every terminal/locale) so the cursor-move
  # `paint(r, c)` lands on the right visual column in CJK / East Asian width
  # environments too.
  function done_mark() {
    if (current_phase == "screening")      return "\033[36m#\033[0m"
    if (current_phase == "dp-refine")      return "\033[1;35m#\033[0m"
    if (current_phase == "dp-full")        return "\033[1;32m#\033[0m"
    return "\033[37m?\033[0m"
  }

  function in_progress_mark() {
    return "\033[1;33mo\033[0m"
  }

  function paint(r, c, mark) {
    printf "\033[%d;%dH%s", 3 + r, 1 + c, mark
  }

  function status(text) {
    printf "\033[1;1H\033[K%s", text
  }

  /"event":"cell_start"/ {
    if (match($0, /"row":[0-9]+/) == 0) next
    row = substr($0, RSTART + 6, RLENGTH - 6) + 0
    if (match($0, /"col":[0-9]+/) == 0) next
    col = substr($0, RSTART + 6, RLENGTH - 6) + 0

    if (prev_row >= 0) paint(prev_row, prev_col, done_mark())
    paint(row, col, in_progress_mark())
    prev_row = row; prev_col = col
    fflush()
    next
  }

  /"event":"phase_start"/ {
    current_phase = get_phase($0)
    status("Phase: " current_phase " starting")
    fflush()
    next
  }

  /"event":"phase_end"/ {
    if (prev_row >= 0) {
      paint(prev_row, prev_col, done_mark())
      prev_row = -1; prev_col = -1
    }
    status("Phase: " get_phase($0) " done")
    fflush()
    next
  }
  '
else
  # Plain mode: one line per phase boundary + aggregated dp-node summary at
  # phase_end. No ANSI, no per-event spam — suitable for agent / CI / log
  # consumers where in-place updates would be noise.
  awk '
  BEGIN {
    current_phase = ""; cell_count = 0
    saddle = 0; nash = 0; pruned = 0
    max_depth = 0; samples = 0
  }

  function get_phase(line) {
    if (match(line, /"phase":"[^"]+"/) > 0) {
      return substr(line, RSTART + 9, RLENGTH - 10)
    }
    return "?"
  }

  function get_total(line) {
    if (match(line, /"total":[0-9]+/) > 0) {
      return substr(line, RSTART + 8, RLENGTH - 8) + 0
    }
    return 0
  }

  /"event":"phase_start"/ {
    ph = get_phase($0); total = get_total($0)
    current_phase = ph; cell_count = 0
    saddle = 0; nash = 0; pruned = 0; max_depth = 0; samples = 0
    if (total > 0) printf "[viz] phase %s start (cells=%d)\n", ph, total
    else           printf "[viz] phase %s start\n", ph
    fflush()
    next
  }

  /"event":"cell_start"/ { cell_count = cell_count + 1; next }

  /"event":"dp_node"/ {
    samples = samples + 1
    if (match($0, /"depth":[0-9]+/) > 0) {
      d = substr($0, RSTART + 8, RLENGTH - 8) + 0
      if (d > max_depth) max_depth = d
    }
    if (match($0, /"classification":"[^"]+"/) > 0) {
      k = substr($0, RSTART + 18, RLENGTH - 19)
      if (k == "saddle") saddle = saddle + 1
      else if (k == "nash") nash = nash + 1
      else if (k == "pruned") pruned = pruned + 1
    }
    next
  }

  /"event":"phase_end"/ {
    ph = get_phase($0)
    parts = ""
    if (cell_count > 0) {
      parts = "cells=" cell_count
    }
    if (samples > 0) {
      sep = (parts == "") ? "" : " | "
      parts = parts sep sprintf("dp samples=%d max_depth=%d saddle=%d nash=%d pruned=%d",
                                samples, max_depth, saddle, nash, pruned)
    }
    if (parts == "") {
      printf "[viz] phase %s done\n", ph
    } else {
      printf "[viz] phase %s done (%s)\n", ph, parts
    }
    fflush()
    next
  }
  '
fi
