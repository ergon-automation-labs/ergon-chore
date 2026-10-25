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
