import Config

config :bot_army_chore, :task_store, BotArmyChore.TaskStoreMock

config :bot_army_chore, BotArmyChore.Repo,
  database: System.get_env("BOT_ARMY_CHORE_DB_NAME", "bot_army_chore_test"),
  hostname: System.get_env("BOT_ARMY_CHORE_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_CHORE_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_CHORE_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_CHORE_DB_PASSWORD", "postgres"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1
