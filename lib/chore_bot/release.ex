defmodule ChoreBot.Release do
  @moduledoc """
  Release tasks for the Chore bot.

  Migrations are run via the shared BotArmyLibraryRuntime.Ecto.MigrationRunner:

      /path/to/chore_bot/bin/chore_bot eval 'ChoreBot.Release.migrate()'

  Called from Salt during bot deployment, before the bot starts.
  """

  alias BotArmyLibraryRuntime.Ecto.MigrationRunner

  @app :bot_army_chore

  def migrate do
    MigrationRunner.run(
      repo_module: BotArmyChore.Repo,
      app_module: @app
    )
  end
end
