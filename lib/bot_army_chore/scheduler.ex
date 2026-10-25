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
    tenant_id = BotArmyLibraryCore.Tenant.default_tenant_id()

    case task_store().list_all(tenant_id) do
      {:ok, tasks} ->
        tasks
        |> Enum.filter(&open_and_dated?/1)
        |> Enum.map(fn task -> {task["id"], days_overdue(task["due_date"])} end)
        # The tiers start at "1+ days overdue", so a chore due today is not yet one of them.
        # Keeping the zeroes here made every future-dated chore look overdue to the reminder
        # loop the moment this started returning them; the filter is what makes the number
        # mean what its name says.
        |> Enum.filter(fn {_id, days} -> days > 0 end)

      {:error, reason} ->
        Logger.error("[Scheduler] Could not read the chore list: #{inspect(reason)}")
        []
    end
  rescue
    e ->
      Logger.error("[Scheduler] Error checking overdue tasks: #{inspect(e)}")
      []
  end

  # Only a chore that is still open has an overdue *state*. A completed chore keeps its
  # `due_date`, so without this filter every finished chore would be reminded about forever —
  # and a reminder about work already done is the one kind that teaches her to ignore the rest.
  defp open_and_dated?(task) when is_map(task) do
    task["status"] in ["pending", "in_progress"] and is_binary(task["due_date"])
  end

  defp open_and_dated?(_), do: false

  # The store's own wire shape carries `due_date` as an ISO date string, so this parses rather
  # than pattern-matching a struct: the previous version compared a string to a `DateTime` and
  # raised on every chore, which the rescue turned into "no overdue chores" forever.
  defp days_overdue(due_date) when is_binary(due_date) do
    case Date.from_iso8601(due_date) do
      {:ok, date} -> max(Date.diff(Date.utc_today(), date), 0)
      _ -> 0
    end
  end

  defp days_overdue(_), do: 0

  defp task_store, do: Application.get_env(:bot_army_chore, :task_store, BotArmyChore.TaskStore)
end
