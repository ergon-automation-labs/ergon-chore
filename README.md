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
