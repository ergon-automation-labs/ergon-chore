defmodule BotArmyChore.Application do
  @moduledoc """
  BotArmyChore application supervisor.

  Manages chore bot services:
  - NATS message consumer
  - Chore scheduler
  - Assignment manager
  """

  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children = []
    |> maybe_add_repo()
    |> maybe_add_task_store()
    |> maybe_add_scheduler()
    |> maybe_add_consumer()

    opts = [strategy: :one_for_one, name: BotArmyChore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyChore.Repo | children]
  end

  defp maybe_add_task_store(children) do
    if @env == :test, do: children, else: [{BotArmyChore.TaskStore, []} | children]
  end

  defp maybe_add_scheduler(children) do
    if @env == :test, do: children, else: [{BotArmyChore.Scheduler, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyChore.NATS.Consumer, []} | children]
  end
end
