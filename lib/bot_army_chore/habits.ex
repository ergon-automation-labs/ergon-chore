defmodule BotArmyChore.Habits do
  @moduledoc """
  A habit is a recurring chore, and a count of how often it has actually been done.

  Nothing here is configured. A habit exists because a chore with a cadence exists, its
  window comes from that cadence, and its name is the chore's name — so there is no second
  list to maintain and no place for the two to drift. A habit you tick by hand is another
  thing to fail at; a habit derived from a press you were making anyway is a fact.

  ## Two kinds of "last done"

  `tasks.completed_at` is overwritten on every completion. It survives restarts and it can
  answer *when*, but never *how often*. `chore_completions` rows are the history that
  answers *how often* — and they only exist from the version that started writing them.

  So each habit carries a `basis`:

    * `"recorded"` — there is at least one completion row; the count is real.
    * `"last_only"` — a completion happened before the history existed; `last_done` is
      real and `done_in_window` is `nil`, because a count that included occasions nobody
      wrote down would be invented.
    * `"never"` — nothing has ever been recorded, and the chore has no `completed_at`.

  A surface draws `done_in_window` only when it is not `nil`, and says "last done …"
  otherwise. That is the whole point of the field: the number is absent rather than wrong.

  ## The wording

  `summary` is a fact, phrased to be read at a glance and never as a score: "three of the
  last four weeks", "last done 8 days ago", "not done yet". There is no streak here and no
  "broken" — a missed week is information, and a system that grades it is a system that
  gets abandoned.
  """

  @type habit :: %{
          id: String.t(),
          title: String.t(),
          cadence: String.t(),
          window_days: pos_integer(),
          expected_in_window: pos_integer(),
          done_in_window: non_neg_integer() | nil,
          last_done: String.t() | nil,
          days_since_done: non_neg_integer() | nil,
          next_due_at: String.t() | nil,
          due_in_days: integer() | nil,
          basis: String.t(),
          summary: String.t()
        }

  # {cadence in days, window in days}. The window is what "recently" means for a chore
  # that comes round at that cadence: four weeks of a weekly chore, a week of a daily one.
  @windows %{
    "daily" => {1, 7},
    "weekly" => {7, 28},
    "monthly" => {30, 90},
    "yearly" => {365, 365}
  }

  @units %{
    "daily" => {"day", "days"},
    "weekly" => {"week", "weeks"},
    "monthly" => {"month", "months"},
    "yearly" => {"year", "years"}
  }

  @doc "The cadences a habit can have. `once` is not one: it cannot come round again."
  def cadences, do: Map.keys(@windows)

  @doc """
  Derive habits from chores and the completions recorded against them.

  `tasks` are the store's task maps (string keys); `completions` are
  `BotArmyChore.Schemas.ChoreCompletion` rows (or maps with `:task_id` and
  `:completed_at`). Sorted most-overdue first, then by name.
  """
  @spec derive([map()], [map()], DateTime.t()) :: [habit]
  def derive(tasks, completions, now \\ DateTime.utc_now()) do
    by_task = Enum.group_by(completions, & &1.task_id)

    tasks
    |> Enum.filter(&habit?/1)
    |> Enum.map(&habit(&1, Map.get(by_task, &1["id"]) || [], now))
    |> Enum.sort_by(fn h -> {h.due_in_days || 9_999, h.title} end)
  end

  @doc "A chore is a habit when it comes round again and has not been put away."
  def habit?(task) do
    Map.has_key?(@windows, task["frequency"]) && task["status"] != "archived"
  end

  defp habit(task, rows, now) do
    cadence = task["frequency"]
    {unit_days, window_days} = Map.fetch!(@windows, cadence)
    expected = div(window_days, unit_days)
    since = DateTime.add(now, -window_days, :day)

    recorded =
      rows
      |> Enum.map(&as_datetime(&1.completed_at))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&DateTime.to_unix/1)

    # `last_done` prefers the history, and falls back to the column that survives restarts
    # but is overwritten. The fallback is why `basis` is not simply "recorded or not".
    {last_done, basis} =
      case {List.last(recorded), as_datetime(task["completed_at"])} do
        {nil, nil} -> {nil, "never"}
        {nil, row} -> {row, "last_only"}
        {row, _} -> {row, "recorded"}
      end

    done_in_window =
      case basis do
        "recorded" -> Enum.count(recorded, &(DateTime.compare(&1, since) != :lt))
        _ -> nil
      end

    next_due_at = as_datetime(task["next_due_at"])
    days_since_done = days_since(last_done, now)
    due_in_days = days_until(next_due_at, now)

    %{
      id: task["id"],
      title: task["title"],
      cadence: cadence,
      window_days: window_days,
      expected_in_window: expected,
      done_in_window: done_in_window,
      last_done: iso(last_done),
      days_since_done: days_since_done,
      next_due_at: iso(next_due_at),
      due_in_days: due_in_days,
      basis: basis,
      summary: summary(basis, done_in_window, expected, cadence, days_since_done)
    }
  end

  # Facts, in the order a person would say them. No adjectives about performance.
  defp summary("recorded", done, expected, cadence, _days) do
    {one, many} = Map.fetch!(@units, cadence)
    "#{words(done)} of the last #{words(expected)} #{pluralise(expected, one, many)}"
  end

  defp summary("last_only", _done, _expected, _cadence, days) when is_integer(days),
    do: "last done #{ago(days)}"

  defp summary("last_only", _done, _expected, _cadence, _days), do: "last done —"

  defp summary(_basis, _done, _expected, _cadence, _days), do: "not done yet"

  defp words(0), do: "none"
  defp words(1), do: "one"
  defp words(2), do: "two"
  defp words(3), do: "three"
  defp words(4), do: "four"
  defp words(5), do: "five"
  defp words(6), do: "six"
  defp words(7), do: "seven"
  defp words(n), do: Integer.to_string(n)

  defp pluralise(1, one, _many), do: one
  defp pluralise(_n, _one, many), do: many

  @doc "How a gap is said out loud. Zero days is today, not \"0 days ago\"."
  def ago(days) when days <= 0, do: "today"
  def ago(1), do: "yesterday"
  def ago(days), do: "#{days} days ago"

  # Whole days elapsed, floored — so seven days and fourteen hours ago is "7 days
  # ago", not 8, and a chore overdue by nineteen hours is -1, not 0. `nil` when there
  # is no instant to compare: a chore that never came due has no answer, and zero
  # would be a lie.
  defp days_since(nil, _now), do: nil

  defp days_since(at, now),
    do: at |> as_datetime() |> then(&maybe_diff(now, &1, 1))

  defp days_until(nil, _now), do: nil

  defp days_until(at, now),
    do: at |> as_datetime() |> maybe_diff(now, 1)

  defp maybe_diff(nil, _now, _sign), do: nil

  # Floored, not truncated: `trunc` rounds toward zero, so a chore that came due
  # nineteen hours ago read `due_in_days: 0` — "due today" for something already
  # overdue. Floor keeps the sign honest: negative is always overdue.
  defp maybe_diff(at, now, sign),
    do: Integer.floor_div(DateTime.diff(at, now, :second), 86_400) * sign

  @doc false
  # The store hands dates in three shapes: a `DateTime`, an ISO 8601 string with an
  # offset, and the naive second-precision column as an ISO string with no offset. They
  # all mean UTC here.
  def as_datetime(nil), do: nil
  def as_datetime(%DateTime{} = dt), do: dt
  def as_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  def as_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  def as_datetime(_), do: nil

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
