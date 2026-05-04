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
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_task_store()
      |> maybe_add_scheduler()
      |> maybe_add_pulse_publisher()
      |> maybe_add_intent_evaluator()
      |> maybe_add_veto_listener()
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

  defp maybe_add_pulse_publisher(children) do
    if @env == :test, do: children, else: [{BotArmyChore.PulsePublisher, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyChore.NATS.Consumer, []} | children]
  end

  defp maybe_add_intent_evaluator(children) do
    if @env == :test, do: children, else: [{BotArmyChore.IntentEvaluator, []} | children]
  end

  defp maybe_add_veto_listener(children) do
    if @env == :test do
      children
    else
      veto_rules = [
        [
          bot: "gtd",
          action: "nudge",
          custom: &BotArmyChore.VetoRules.veto_nudge_when_overdue_chores/1
        ]
      ]

      child = {BotArmyRuntime.Intent.VetoListener, rules: veto_rules, bot_name: "chore"}
      [child | children]
    end
  end
end
