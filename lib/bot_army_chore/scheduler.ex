defmodule BotArmyChore.Scheduler do
  @moduledoc """
  GenServer for managing chore scheduling and recurring task checks.

  Periodically checks for overdue recurring tasks and publishes notifications
  with 3-tier escalation system.
  """

  use GenServer
  require Logger

  @tier1_hours 24    # first reminder (1 day overdue)
  @tier2_hours 72    # second reminder (3 days overdue)
  @tier3_hours 168   # escalated (1 week overdue)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Chore Scheduler started")
    schedule_next_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_due, state) do
    check_overdue_recurring()
    schedule_next_check()
    {:noreply, state}
  end

  defp schedule_next_check do
    # Schedule for next midnight
    ms_until_midnight = ms_until_next_midnight()
    Process.send_after(self(), :check_due, ms_until_midnight)
  end

  defp ms_until_next_midnight do
    now = DateTime.utc_now()
    # Calculate tomorrow at 00:00:00 UTC
    tomorrow_at_midnight = now
      |> DateTime.add(1, :day)
      |> then(fn dt -> DateTime.new!(DateTime.to_date(dt), ~T[00:00:00], "Etc/UTC") end)
    DateTime.diff(tomorrow_at_midnight, now, :millisecond)
  end

  defp check_overdue_recurring do
    tasks = BotArmyChore.TaskStore.list_overdue_recurring()
    Logger.info("Found #{length(tasks)} overdue recurring tasks")
    now = DateTime.utc_now()

    Enum.each(tasks, fn task ->
      hours = hours_overdue(task, now)
      level = task["notification_level"] || 0

      cond do
        hours >= @tier3_hours and level < 3 ->
          publish_notification(task, 3, "urgent")
          BotArmyChore.TaskStore.set_notification_level(task["id"], 3, now)
        hours >= @tier2_hours and level < 2 ->
          publish_notification(task, 2, "overdue")
          BotArmyChore.TaskStore.set_notification_level(task["id"], 2, now)
        hours >= @tier1_hours and level < 1 ->
          publish_notification(task, 1, "due")
          BotArmyChore.TaskStore.set_notification_level(task["id"], 1, now)
        true -> :ok
      end
    end)
  end

  defp hours_overdue(%{"next_due_at" => due_str}, now) when is_binary(due_str) do
    case DateTime.from_iso8601(due_str) do
      {:ok, due, _} -> max(0, div(DateTime.diff(now, due, :second), 3600))
      _ -> 0
    end
  end
  defp hours_overdue(_, _), do: 0

  defp publish_notification(task, level, urgency) do
    event_data = %{
      "event" => "chore.task.notification",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_chore",
      "source_node" => get_node_name(),
      "triggered_by" => "chore.scheduler",
      "schema_version" => "1.0",
      "payload" => %{
        "task_id" => task["id"],
        "title" => task["title"],
        "frequency" => task["frequency"],
        "assigned_to" => task["assigned_to"],
        "notification_level" => level,
        "urgency" => urgency,
        "next_due_at" => task["next_due_at"]
      }
    }
    BotArmyChore.NATS.Publisher.publish(event_data)
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end
end
