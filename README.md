# BotArmyChore

Chore and household task management bot implementation for the Bot Army ecosystem.

Manages chore scheduling, assignment, and completion tracking.

## Building

```bash
mix deps.get
mix test
```

## Running

```bash
iex -S mix
```

## Architecture

- **NATS Consumer** - Listens for chore-related messages
- **Chore Scheduler** - Manages recurring chore schedules
- **Assignment Manager** - Handles chore assignments and tracking

## Subjects a checklist door reads

- `chore.task.list` (request/reply) — the **open** chores (`pending`, `in_progress`), due first,
  undated last, oldest first within a day. Answers `{"ok": true, "data": {"chores": [...]}}` with
  `id`, `title`, `category`, `frequency`, `status`, `due_date`, `location`, `assigned_to` per
  chore. A store that cannot answer is `{"ok": false, "error": …, "code": "read_failed"}` — an
  empty list and an unreadable one are different answers, because a card that drew the second as
  the first would tell her the house is clear when nobody looked.
- `chore.task.create` (request/reply) — requires `title`, `category`, `frequency`
  (`once|daily|weekly|monthly|yearly`); answers `{"ok": true, "data": {"chore": {...}}}` with the
  stored row, or `{"ok": false, "error": …}` in words.
- `chore.task.complete` (request/reply) — one press, `{"task_id": ...}`, answering the completed
  row or `code: "not_found"`.
- `chore.task.uncomplete` (request/reply) — the undo for a press that was a mistake. Deletes the
  **latest** recorded occasion and restores the `next_due_at` that completion displaced (stored
  on the completion row as `next_due_at_before`; recomputing from the cadence would move a weekly
  chore to "tonight + 7" and make the undo a different schedule). Answers the row, or
  `code: "no_completion"` when there is nothing to take back — a press that reports success after
  changing nothing is the same lie as one that reports failure after doing the work.
- `chore.task.archive` (request/reply) — "I stopped doing this one". Sets `archived_at`; the row
  keeps its id, its schedule and its completion history, and every read filters the mark, so the
  chore leaves the card and the habit list without anything being destroyed.
- `chore.task.restore` (request/reply) — clears the mark. Because the row was never deleted, what
  comes back is the *same* chore: same id, same history, same schedule. Archive/restore is the
  pair a door draws as one line ("Put away · Undo"), not a delete behind a confirmation.

The three verbs a door asks are the fleet's `Reply` envelope (`BotArmyLibraryRuntime.NATS.Reply`),
the same shape `fitness.set.list` answers with, so a surface that draws one list can draw this
one. They accept two bodies: the fleet's envelope (`"payload"` holds the arguments) and a flat
request/reply body (arguments at the top level) — `"payload"` for an envelope, the top level for a
flat body, one rule read in the handler. Both `create` and `complete` also answer when a caller
leaves no reply address, which is what the discord check-in does: the work is done, no answer is
owed, and a missing broker is a lost answer rather than a lost chore.
- `chore.schedule.list` — the **overdue recurring** half only (what the reminder loop believes is
  late). Not the household's working list: "overdue" is a judgement, and a door opening on it
  would be opening on an accusation.

The reminder loop (`BotArmyChore.Scheduler`) reads the same store and counts only chores that are
still open and at least one day past due; a completed chore keeps its `due_date` and is never
reminded about again.

- `chore.habit.list` (request/reply) — **derived** habits: one per recurring chore, with
  `done_in_window`, `expected_in_window`, `last_done`, `days_since_done`, `next_due_at`,
  `due_in_days` and a `summary` in words ("three of the last four weeks"). There is no habit
  store and no habit subject of its own — the chore *is* the habit, so a habit cannot exist for
  something she is not already doing, and there is no second list to maintain.
  `done_in_window` is `nil` when the history does not support a count (`basis: "last_only"`):
  `tasks.completed_at` is overwritten on every completion, so before `chore_completions` existed
  it could say *when* but never *how often*, and a count in its place would be invented.

### A habit is a chore that comes round again

`chore_completions` holds one row per completion, written in the same transaction as the
completion itself, so the chore's `completed_at` and its history cannot disagree. A habit's window
comes from the chore's own cadence (weekly → four weeks, daily → one week, monthly → three months,
yearly → one year), and `summary` is a fact rather than a score: "three of the last four weeks",
"last done 7 days ago", "not done yet". There is deliberately no streak, no "broken", and no red —
a missed week is information, and a system that grades it is a system that gets abandoned.

### A chore written down without a day is on the list today

`chore.task.create` does not require `due_date`, and it no longer leaves it empty: a chore created
without one is dated **the day it was written**. `frequency` says how often a chore comes back, not
when it first counts — "every week" added on Sunday is due today and again next week, not due next
Sunday — and a row with no `due_date` never satisfies the reminder loop's `open_and_dated?/1`, so
such a chore sat on the card while the loop that is supposed to speak about it had nothing to say
about it, forever. A day the caller *did* send is kept exactly as sent, including one in the past:
the bot does not know better than the person who wrote it down, and `due_date: nil` or `""` means
the same as leaving it out.

## Message Schemas

Schemas are defined in `bot_army_schemas_chore` and deployed to `/etc/bot_army/schemas/chore/`

## Dependencies

- `bot_army_core` - Core NATS decoder and envelope handling
- `nats` - NATS client library
- `jason` - JSON encoding/decoding
- `logger_json` - JSON logging

## Development

```bash
make setup    # Install dependencies
make test     # Run tests
make check    # Run all checks
```

## Related Repositories

- `bot_army_schemas_chore` - Chore message schemas
- `bot_army_core` - Core library
- `bot_army_infra` - Deployment infrastructure
