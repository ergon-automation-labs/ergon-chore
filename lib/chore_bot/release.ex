defmodule ChoreBot.Release do
  @moduledoc """
  Release tasks for the Chore bot.

  Used for running database migrations from a compiled OTP release:

      /path/to/chore_bot/bin/chore_bot eval 'ChoreBot.Release.migrate()'
  """

  @app :bot_army_chore

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
