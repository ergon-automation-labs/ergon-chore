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
  undated last, oldest first within a day. Answers `{"chores": [...]}` with `id`, `title`,
  `category`, `frequency`, `status`, `due_date`, `location`, `assigned_to` per chore, or
  `{"chores": [], "error": "read_failed"}` — an empty list and an unreadable one are different
  answers, because a card that drew the second as the first would tell her the house is clear
  when nobody looked.
- `chore.task.create` — requires `title`, `category`, `frequency` (`once|daily|weekly|monthly|yearly`).
- `chore.task.complete` — one press, `{"task_id": ...}`.
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
