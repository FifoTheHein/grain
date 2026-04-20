# Running Timer Badge — Design Spec

**Date:** 2026-04-20

## Overview

When a Harvest time entry has `is_running: true`, the `DurationPill` on its `TimeEntryCard` should visually indicate the timer is active: the pill turns solid orange and gains a small play-arrow badge overlaid at the bottom-right corner.

## Model

**File:** `lib/models/time_entry.dart` — `TimeEntry` class

- Add `final bool isRunning` field, defaulting to `false`.
- Parse in `fromJson`: `isRunning: json['is_running'] as bool? ?? false`.

## DurationPill

**File:** `lib/widgets/duration_pill.dart`

- Rename the existing `active` parameter to `running` (same bool semantics, clearer name).
- When `running: true`, the pill background becomes `HarvestTokens.brand` (solid orange) and text becomes white — this is the existing `active` behaviour, now driven by `running`.
- Wrap the circle `Container` in a `Stack`. When `running`, position a badge at the bottom-right:
  - Outer circle: ~14px diameter, `HarvestTokens.brand` background, white border (1–1.5px) to lift it off the pill.
  - Inner icon: `Icons.play_arrow`, ~9px, white.

## TimeEntryCard

**File:** `lib/widgets/time_entry_card.dart`

- Pass `running: entry.isRunning` to `DurationPill`. No other changes.

## Other Callsites

**`lib/screens/edit_time_screen.dart`** uses `DurationPill(hours: ..., size: 32)` without `active`, so the parameter rename has no effect there — it will continue to use `running: false` by default.

## Out of Scope

- No stop/start timer actions — indicator only.
- No animation on the badge or pill.
