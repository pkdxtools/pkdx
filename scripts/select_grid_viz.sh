#!/usr/bin/env bash
# select_grid_viz.sh — Live 60×60 grid visualiser for `pkdx select --progress=json`.
#
# Reads JSON Lines on stdin (one event per line), draws a fixed grid of cells,
# updates the cell at (row, col) on each `cell_start` event, and tags it as
# done when the next cell_start arrives or the phase ends. Phases are colour-
# coded so screening fill (cyan) is visually distinct from dp-refine fill
# (magenta). The current in-progress cell is rendered as ▢ in yellow.
#
# Usage:
#   cat input.json \
#     | bin/pkdx select --progress=json 2> >(scripts/select_grid_viz.sh) \
#     > result.json
#
# Env:
#   ROWS / COLS — grid dims (default 60×60, matches 6v6 single)

set -u

ROWS=${ROWS:-60}
COLS=${COLS:-60}

# Hide cursor while drawing; restore + park below grid on exit.
cleanup() { printf '\033[?25h\033[%d;1H\n' "$((ROWS + 4))"; }
trap cleanup EXIT INT TERM
printf '\033[?25l'

awk -v ROWS="$ROWS" -v COLS="$COLS" '
BEGIN {
  printf "\033[2J\033[H"
  printf "Phase: (waiting)\n\n"
  for (r = 0; r < ROWS; r++) {
    for (c = 0; c < COLS; c++) printf "\033[2m·\033[0m"
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
# ▢ (in-progress) is replaced by ■ (filled), colour-coded per phase so the
# screening fill (cyan) and dp-refine fill (magenta) remain distinguishable.
function done_mark() {
  if (current_phase == "screening")      return "\033[36m■\033[0m"
  if (current_phase == "dp-refine")      return "\033[1;35m■\033[0m"
  if (current_phase == "dp-full")        return "\033[1;32m■\033[0m"
  return "\033[37m?\033[0m"
}

function in_progress_mark() {
  return "\033[1;33m▢\033[0m"
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
