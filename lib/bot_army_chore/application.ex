defmodule BotArmyChore.Application do
  @moduledoc """
  BotArmyChore application supervisor.

  Manages chore bot services:
  - NATS message consumer
  - Chore scheduler
  - Assignment manager
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database connection
      BotArmyChore.Repo,

      # Chore task storage (in-memory + Ecto persistence)
      {BotArmyChore.TaskStore, []},

      # NATS connection and consumer
      {BotArmyChore.NATS.Consumer, []}
    ]

    opts = [strategy: :one_for_one, name: BotArmyChore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
