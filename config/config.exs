import Config

# Ecto repositories for migrations
config :bot_army_chore, ecto_repos: [BotArmyChore.Repo]

# Database configuration from Salt/Helm environment variables
config :bot_army_chore, BotArmyChore.Repo,
  database: System.get_env("BOT_ARMY_CHORE_DB_NAME", "bot_army_chore"),
  hostname: System.get_env("BOT_ARMY_CHORE_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_CHORE_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_CHORE_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_CHORE_DB_PASSWORD", "postgres"),
  pool_size: 10
