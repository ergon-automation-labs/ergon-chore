import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# Database configuration at runtime
# Priority: BOT_ARMY_CHORE_DB_* (set by Salt/Jenkins) > DATABASE_* (from .env for local dev) > defaults
if config_env() != :test do
  alias BotArmyLibraryRuntime.Ecto.RuntimeDbConfig

  db_config =
    RuntimeDbConfig.resolve("BOT_ARMY_CHORE", database: "ergon_chore", port: 30006)

  config(
    :bot_army_chore,
    BotArmyChore.Repo,
    Keyword.merge(db_config, [
      pool_size: RuntimeDbConfig.pool_size("BOT_ARMY_CHORE", 10),
      ssl: false
    ])
  )
end
