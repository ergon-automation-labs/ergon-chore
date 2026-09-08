defmodule BotArmyChore.Scheduler do
  @moduledoc """
  Chore task reminders via BotArmyLibraryRuntime.Reminders.

  Provides check function for BotArmyLibraryRuntime.Reminders to determine
  which tasks are overdue and how many days past due.

  Uses urgency escalation:
  - "due": 1+ days overdue
  - "overdue": 3+ days overdue
  - "urgent": 7+ days overdue
  """

  require Logger

  @doc """
  Check for overdue chore tasks.

  Called by BotArmyLibraryRuntime.Reminders on a periodic basis (default: hourly).
  Returns list of {task_id, days_overdue} tuples for tasks that are overdue.
  """
  def check_overdue_tasks do
    BotArmyChore.ChoreStore.get_all_tasks()
    |> Enum.filter(fn task ->
      task.due_date && DateTime.compare(DateTime.utc_now(), task.due_date) == :gt
    end)
    |> Enum.map(fn task ->
      days_overdue = calculate_days_overdue(task.due_date)
      {task.id, days_overdue}
    end)
  rescue
    e ->
      Logger.error("[Scheduler] Error checking overdue tasks: #{inspect(e)}")
      []
  end

  defp calculate_days_overdue(due_date) do
    due_datetime =
      if is_struct(due_date, DateTime) do
        due_date
      else
        DateTime.new!(due_date, ~T[00:00:00])
      end

    DateTime.utc_now()
    |> DateTime.diff(due_datetime, :second)
    # seconds per day
    |> div(86_400)
  end
end
