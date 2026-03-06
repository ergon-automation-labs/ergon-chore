# CLAUDE.md

Guidance for Claude Code when working with `bot_army_chore`.

---

## Purpose

**bot_army_chore** is the chore and household task management bot implementation.

Handles:
- Recurring chore scheduling
- Chore assignment and rotation
- Completion tracking and reminders
- Status reporting and accountability

---

## File Organization

```
.
├── lib/
│   ├── bot_army_chore.ex                # Main module
│   └── bot_army_chore/
│       ├── application.ex                # Application supervisor
│       ├── nats/
│       │   └── consumer.ex               # NATS message consumer
│       └── handlers/
│           ├── schedule_handler.ex
│           ├── assignment_handler.ex
│           └── completion_handler.ex
├── test/
│   ├── test_helper.exs
│   └── bot_army_chore/
│       ├── nats/
│       │   └── consumer_test.exs
│       └── handlers/
│           └── schedule_handler_test.exs
├── mix.exs
├── CLAUDE.md
└── README.md
```

---

## Core Dependencies

- **bot_army_core** - NATS envelope decoding, schema validation
- **nats** - NATS client for message publishing/subscribing
- **jason** - JSON encoding/decoding
- **logger_json** - Structured JSON logging

The bot depends on schemas deployed by `bot_army_schemas_chore` at `/etc/bot_army/schemas/chore/`

---

## Development Workflow

### Setup

```bash
mix deps.get
mix test
```

### Key Modules to Implement

1. **BotArmyChore.NATS.Consumer** - Subscribe to NATS subjects
2. **BotArmyChore.Handlers.ScheduleHandler** - Handle chore scheduling
3. **BotArmyChore.Handlers.AssignmentHandler** - Manage chore assignments
4. **BotArmyChore.Handlers.CompletionHandler** - Track completions

### Message Subjects

The bot listens to and publishes:
- `chore.schedule.*` - Chore scheduling operations
- `chore.assignment.*` - Chore assignment operations
- `chore.completion.*` - Completion tracking

All messages follow the core envelope structure from `bot_army_core`.

---

## Testing

```bash
mix test                    # Run all tests
mix test --cover            # With coverage
mix credo                   # Linting
mix dialyzer                # Static analysis
```

---

## Deployment

This bot is deployed via Salt from `bot_army_infra`:

```bash
cd ../bot_army_infra
make deploy-bot BOT=chore
```

Deployment happens after:
1. Core schemas deployed
2. bot_army_core library deployed

---

## Related Repositories

- `bot_army_schemas_chore` - Chore message schemas
- `bot_army_core` - Core library and NATS decoder
- `bot_army_infra` - Deployment infrastructure

---

## Agent Workflow Pattern

**Effective use of Claude Code agents when developing this bot.**

This follows the polyrepo agent strategy documented in `bot_army_infra/CLAUDE.md`.

### When to Use Haiku Agents

- Exploring handler implementations and understanding existing patterns
- Reading test files to understand expected behavior
- Diagnostics: checking test failures, understanding error logs
- Code search: finding specific handlers or NATS subjects
- Verification: running tests, checking message flow

**Why**: Fast iteration loop, perfect for understanding how other bots are structured.

### When to Use Sonnet Agents

- Implementing new handlers or business logic
- Designing complex scheduling and rotation algorithms
- Multi-handler integrations and chore lifecycle management
- Refactoring handlers for new requirements
- Performance optimizations

**Why**: Deep reasoning ensures handlers are correct, rotation logic is fair and maintainable, and state transitions are sound.

### Example: Add Chore Rotation Scheduling

```
User: "Add fair rotation scheduling based on history"
  ↓
1. Haiku (Explore): Read existing schedule_handler.ex and assignment_handler.ex
  ↓
2. Sonnet (Plan): Design rotation algorithm, identify fairness criteria, plan state tracking
   Determine how to handle skipped chores and special cases
  ↓
3. Sonnet (Implement): Add rotation logic, update assignment handler, add tests
  ↓
4. Haiku (Verify): Run test suite, validate rotation fairness
```
