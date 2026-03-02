defmodule BotArmyChore.Repo do
  @moduledoc """
  Ecto Repository for the Chore bot.

  Provides database access for chore tasks with PostgreSQL backend.
  """

  use Ecto.Repo,
    otp_app: :bot_army_chore,
    adapter: Ecto.Adapters.Postgres
end
