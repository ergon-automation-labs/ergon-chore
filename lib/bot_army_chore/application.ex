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
      |> maybe_add_outcome_tracker()
      |> storage_first()

    opts = [strategy: :one_for_one, name: BotArmyChore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Each `maybe_add_*` prepends, so the pipeline above yields its children in
  # reverse order and storage ended up *last*: the store started before the repo
  # that answers it. Every boot then read nothing (there was no pool yet), and
  # the old rescue turned that into a permanently empty store — thirteen chores
  # in Postgres, answered as an empty house (measured on mini 2026-11-02).
  @doc false
  def storage_first(children) do
    {storage, others} =
      Enum.split_with(children, fn
        BotArmyChore.Repo -> true
        {BotArmyChore.TaskStore, _} -> true
        _ -> false
      end)

    Enum.reverse(storage) ++ others
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyChore.Repo | children]
  end

  defp maybe_add_task_store(children) do
    if @env == :test, do: children, else: [{BotArmyChore.TaskStore, []} | children]
  end

  defp maybe_add_scheduler(children) do
    if @env == :test do
      children
    else
      reminder_config =
        BotArmyLibraryRuntime.Reminders.child_spec(
          bot_name: "chore",
          check_interval_minutes: 60,
          reminders: [
            %{
              thing_type: "task",
              check_fn: &BotArmyChore.Scheduler.check_overdue_tasks/0,
              urgency_tiers: [
                {1, "due"},
                {3, "overdue"},
                {7, "urgent"}
              ]
            }
          ]
        )

      [reminder_config | children]
    end
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
        ],
        [
          bot: "fitness",
          action: "suggest_workout",
          custom: &BotArmyChore.VetoRules.veto_fitness_when_overdue/1
        ]
      ]

      child = {BotArmyLibraryRuntime.Intent.VetoListener, rules: veto_rules, bot_name: "chore"}
      [child | children]
    end
  end

  defp maybe_add_outcome_tracker(children) do
    if @env == :test,
      do: children,
      else: [
        {BotArmyLibraryLearning.OutcomeTracker,
         [repo: BotArmyChore.Repo, name: :chore_outcome_tracker]}
        | children
      ]
  end
end
