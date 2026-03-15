defmodule BotArmyChore.Scheduler do
  @moduledoc """
  GenServer for managing chore scheduling and recurring task checks.

  Periodically checks for overdue recurring tasks and publishes notifications.
  """

  use GenServer
  require Logger

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

    Enum.each(tasks, fn task ->
      publish_due_notification(task)
    end)
  end

  defp publish_due_notification(task) do
    event_data = %{
      "event" => "chore.task.due",
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
        "assigned_to" => task["assigned_to"]
      }
    }

    BotArmyChore.NATS.Publisher.publish(event_data)
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end
end
