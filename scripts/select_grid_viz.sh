#!/usr/bin/env bash
# select_grid_viz.sh — Live progress visualiser for `pkdx select --progress=json`.
#
# Reads JSON Lines on stdin (one event per line) and renders progress in one
# of two modes:
#
# - **TTY mode** (stdout is a terminal): draws a fixed grid of cells. Each
#   `cell_start` paints `o` (yellow) at (row, col); each `cell_done` paints
#   `#` (phase-coloured) at (row, col). Painting is order-independent so the
#   parallel `pkdx select --parallel=N` shards can interleave cell events
#   without breaking the grid — every cell carries its own coordinates and
#   does not depend on previous-cell state. Phase colour comes from the
#   most recent `phase_start`. ASCII glyphs are used deliberately:
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
  # Hide cursor while drawing; restore + park below grid + summary area on
  # exit. Layout: row 1 = status, row 2 = blank, rows 3..ROWS+2 = grid,
  # rows ROWS+3..ROWS+5 = summary, ROWS+7 = parked cursor.
  cleanup() { printf '\033[?25h\033[%d;1H\n' "$((ROWS + 7))"; }
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
    # Per-cell state map. Keys are "r,c" strings, values "prog" / "done".
    # Used by phase_end sanity sweep to upgrade any still-in-progress cells
    # (e.g. a child that crashed between cell_start and cell_done).
    # Per-cell state. Keys are "r,c", values "prog:<phase>" / "done:<phase>".
    # The phase part is recorded so phase_end sanity sweep and reordering-
    # tolerant painting both colour the cell against its originating phase,
    # not the most-recent phase_start marker (which races with child stderr
    # under parallel fan-out).
    delete grid
    # Per-phase progress counters so the status line can show
    # "Phase: <name> N/M" once cell_done events arrive. `done_counts`
    # is keyed by phase string so screening / dp-refine / dp-full all
    # advance independently; `phase_total[<name>]` is grabbed from the
    # PhaseStart `total` field.
    delete done_counts
    delete phase_total
    last_phase = ""
  }

  function get_phase(line,    _) {
    if (match(line, /"phase":"[^"]+"/) > 0) {
      return substr(line, RSTART + 9, RLENGTH - 10)
    }
    return "?"
  }

  function get_total(line,    _) {
    if (match(line, /"total":[0-9]+/) > 0) {
      return substr(line, RSTART + 8, RLENGTH - 8) + 0
    }
    return 0
  }

  function update_status(phase) {
    tot = phase_total[phase] + 0
    done = done_counts[phase] + 0
    if (tot > 0) {
      status(sprintf("Phase: %s  %d/%d", phase, done, tot))
    } else {
      status("Phase: " phase)
    }
  }

  # Coloured "done" mark for cells that completed under each phase.
  # `o` (in-progress) is replaced by `#` (filled), colour-coded per phase so
  # screening fill (cyan) and dp-refine fill (magenta) remain distinguishable.
  # Glyphs are ASCII (width 1 on every terminal/locale) so the cursor-move
  # `paint(r, c)` lands on the right visual column in CJK / East Asian width
  # environments too.
  function done_mark(phase) {
    if (phase == "screening")      return "\033[36m#\033[0m"
    if (phase == "dp-refine")      return "\033[1;35m#\033[0m"
    if (phase == "dp-full")        return "\033[1;32m#\033[0m"
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
    phase = get_phase($0)
    grid[row "," col] = "prog:" phase
    paint(row, col, in_progress_mark())
    last_phase = phase
    update_status(phase)
    fflush()
    next
  }

  /"event":"cell_done"/ {
    if (match($0, /"row":[0-9]+/) == 0) next
    row = substr($0, RSTART + 6, RLENGTH - 6) + 0
    if (match($0, /"col":[0-9]+/) == 0) next
    col = substr($0, RSTART + 6, RLENGTH - 6) + 0
    phase = get_phase($0)
    grid[row "," col] = "done:" phase
    paint(row, col, done_mark(phase))
    done_counts[phase] = (done_counts[phase] + 0) + 1
    last_phase = phase
    update_status(phase)
    fflush()
    next
  }

  /"event":"phase_start"/ {
    phase = get_phase($0)
    phase_total[phase] = get_total($0)
    last_phase = phase
    update_status(phase)
    fflush()
    next
  }

  /"event":"phase_end"/ {
    # Sanity sweep: any cell still marked "prog:<phase>" (e.g. shard
    # crashed between cell_start and cell_done) is upgraded so the grid
    # does not leave stray yellow `o` marks after the phase boundary.
    # The originating phase is read from the per-cell state, not from
    # the surrounding phase_end marker, because under parallel fan-out
    # the parents phase_end can arrive before some child cell_done
    # events do.
    for (key in grid) {
      st = grid[key]
      if (substr(st, 1, 5) == "prog:") {
        ph = substr(st, 6)
        split(key, idx, ",")
        paint(idx[1] + 0, idx[2] + 0, done_mark(ph))
        grid[key] = "done:" ph
        done_counts[ph] = (done_counts[ph] + 0) + 1
      }
    }
    phase = get_phase($0)
    last_phase = phase
    tot = phase_total[phase] + 0
    done = done_counts[phase] + 0
    if (tot > 0) {
      status(sprintf("Phase: %s done  %d/%d", phase, done, tot))
    } else {
      status("Phase: " phase " done")
    }
    fflush()
    next
  }

  # `summary` is the last stderr event emitted by `pkdx select`. Render it on
  # the two lines directly below the grid so the user still sees value /
  # best-selection even when stdout was redirected to a result file.
  /"event":"summary"/ {
    val = ""; expl = ""; mp = ""; op = ""
    my_names = ""; opp_names = ""
    if (match($0, /"value":-?[0-9.eE+-]+/) > 0) {
      val = substr($0, RSTART + 8, RLENGTH - 8)
    }
    if (match($0, /"exploitability":-?[0-9.eE+-]+/) > 0) {
      expl = substr($0, RSTART + 17, RLENGTH - 17)
    }
    if (match($0, /"my_best_p":-?[0-9.eE+-]+/) > 0) {
      mp = substr($0, RSTART + 12, RLENGTH - 12)
    }
    if (match($0, /"opp_best_p":-?[0-9.eE+-]+/) > 0) {
      op = substr($0, RSTART + 13, RLENGTH - 13)
    }
    if (match($0, /"my_best_names":\[[^]]*\]/) > 0) {
      my_names = substr($0, RSTART + 17, RLENGTH - 18)
    }
    if (match($0, /"opp_best_names":\[[^]]*\]/) > 0) {
      opp_names = substr($0, RSTART + 18, RLENGTH - 19)
    }
    # Park summary directly below the grid (row 3 + ROWS = first free line).
    # Absolute cursor positioning is used so no trailing \n needed.
    printf "\033[%d;1H\033[K\033[1mresult\033[0m  value=\033[36m%s\033[0m  exploitability=%s", 3 + ROWS, val, expl
    printf "\033[%d;1H\033[K  my_best=\033[1;33m%s\033[0m (p=%s)", 4 + ROWS, my_names, mp
    printf "\033[%d;1H\033[K  opp_best=\033[1;35m%s\033[0m (p=%s)", 5 + ROWS, opp_names, op
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
    current_phase = ""; done_count = 0
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
    current_phase = ph; done_count = 0
    saddle = 0; nash = 0; pruned = 0; max_depth = 0; samples = 0
    if (total > 0) printf "[viz] phase %s start (cells=%d)\n", ph, total
    else           printf "[viz] phase %s start\n", ph
    fflush()
    next
  }

  /"event":"cell_done"/ { done_count = done_count + 1; next }

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
    if (done_count > 0) {
      parts = "cells=" done_count
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

  /"event":"summary"/ {
    val = ""; mp = ""; op = ""; my_names = ""; opp_names = ""
    if (match($0, /"value":-?[0-9.eE+-]+/) > 0) {
      val = substr($0, RSTART + 8, RLENGTH - 8)
    }
    if (match($0, /"my_best_p":-?[0-9.eE+-]+/) > 0) {
      mp = substr($0, RSTART + 12, RLENGTH - 12)
    }
    if (match($0, /"opp_best_p":-?[0-9.eE+-]+/) > 0) {
      op = substr($0, RSTART + 13, RLENGTH - 13)
    }
    if (match($0, /"my_best_names":\[[^]]*\]/) > 0) {
      my_names = substr($0, RSTART + 17, RLENGTH - 18)
    }
    if (match($0, /"opp_best_names":\[[^]]*\]/) > 0) {
      opp_names = substr($0, RSTART + 18, RLENGTH - 19)
    }
    printf "[viz] result value=%s\n", val
    printf "[viz]        my_best=%s (p=%s)\n", my_names, mp
    printf "[viz]        opp_best=%s (p=%s)\n", opp_names, op
    fflush()
    next
  }
  '
fi
