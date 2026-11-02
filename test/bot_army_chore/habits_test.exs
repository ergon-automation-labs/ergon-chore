defmodule BotArmyChore.HabitsTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyChore.Habits

  @now ~U[2026-11-02 12:00:00Z]

  defp chore(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "11111111-1111-1111-1111-111111111111",
        "title" => "Sweep the steps",
        "frequency" => "weekly",
        "status" => "completed",
        "completed_at" => nil,
        "next_due_at" => nil
      },
      overrides
    )
  end

  defp done(task_id, days_ago) do
    %{task_id: task_id, completed_at: DateTime.add(@now, -days_ago, :day)}
  end

  describe "what counts as a habit" do
    test "a recurring chore is one; a one-off is not, and an archived one is not" do
      habits =
        Habits.derive(
          [
            chore(%{"id" => "weekly", "title" => "Weekly"}),
            chore(%{"id" => "once", "title" => "Once", "frequency" => "once"}),
            chore(%{"id" => "gone", "title" => "Gone", "status" => "archived"})
          ],
          [],
          @now
        )

      assert Enum.map(habits, & &1.id) == ["weekly"]
    end

    test "the window comes from the chore's own cadence, not from configuration" do
      weekly = chore(%{"frequency" => "weekly"})
      daily = chore(%{"id" => "d", "frequency" => "daily"})

      assert %{window_days: 28, expected_in_window: 4} =
               Habits.derive([weekly], [], @now) |> hd()

      assert %{window_days: 7, expected_in_window: 7} =
               Habits.derive([daily], [], @now) |> hd()
    end
  end

  describe "the count is of recorded completions, or it is absent" do
    test "three of the last four weeks, from the completion rows" do
      [habit] =
        Habits.derive(
          [chore()],
          [done(chore()["id"], 1), done(chore()["id"], 8), done(chore()["id"], 15)],
          @now
        )

      assert habit.basis == "recorded"
      assert habit.done_in_window == 3
      assert habit.expected_in_window == 4
      assert habit.summary == "three of the last four weeks"
      assert habit.last_done == "2026-11-01T12:00:00Z"
    end

    test "completions older than the window are not counted, but still name the last one" do
      [habit] =
        Habits.derive(
          [chore()],
          [done(chore()["id"], 10), done(chore()["id"], 40)],
          @now
        )

      assert habit.done_in_window == 1
      assert habit.summary == "one of the last four weeks"
      assert habit.days_since_done == 10
    end

    test "with no history, the overwritten column still says when — and no count is invented" do
      [habit] =
        Habits.derive(
          [chore(%{"completed_at" => "2026-10-25T21:47:34Z"})],
          [],
          @now
        )

      assert habit.basis == "last_only"
      assert habit.done_in_window == nil
      assert habit.summary == "last done 7 days ago"
      assert habit.last_done == "2026-10-25T21:47:34Z"
    end

    test "never done is said plainly" do
      [habit] = Habits.derive([chore()], [], @now)

      assert habit.basis == "never"
      assert habit.done_in_window == nil
      assert habit.last_done == nil
      assert habit.summary == "not done yet"
    end

    test "a recorded completion beats a stale column" do
      [habit] =
        Habits.derive(
          [chore(%{"completed_at" => "2026-09-01T00:00:00Z"})],
          [done(chore()["id"], 2)],
          @now
        )

      assert habit.basis == "recorded"
      assert habit.days_since_done == 2
    end
  end

  describe "ordering and due dates" do
    test "most overdue first, and a chore with no due date last" do
      habits =
        Habits.derive(
          [
            chore(%{"id" => "later", "title" => "Later", "next_due_at" => "2026-11-09T12:00:00Z"}),
            chore(%{"id" => "late", "title" => "Late", "next_due_at" => "2026-10-26T12:00:00Z"}),
            chore(%{"id" => "none", "title" => "None"})
          ],
          [],
          @now
        )

      assert Enum.map(habits, & &1.title) == ["Late", "Later", "None"]
      assert hd(habits).due_in_days == -7
      assert List.last(habits).due_in_days == nil
    end

    test "a due date in the future is positive, not a second kind of overdue" do
      [habit] =
        Habits.derive(
          [chore(%{"next_due_at" => "2026-11-05T12:00:00Z"})],
          [],
          @now
        )

      assert habit.due_in_days == 3
    end

    test "a chore that fell due hours ago is overdue, not due today" do
      # nineteen hours overdue: truncating toward zero called that "due today"
      [habit] =
        Habits.derive(
          [chore(%{"next_due_at" => "2026-11-01T17:00:00Z"})],
          [],
          @now
        )

      assert habit.due_in_days == -1
    end
  end

  describe "date shapes the store actually hands over" do
    test "a naive ISO string with no offset is UTC" do
      assert %DateTime{time_zone: "Etc/UTC"} = Habits.as_datetime("2026-10-25T21:47:34")
    end

    test "a DateTime, a NaiveDateTime and nil" do
      assert Habits.as_datetime(@now) == @now
      assert %DateTime{} = Habits.as_datetime(~N[2026-10-25 21:47:34])
      assert Habits.as_datetime(nil) == nil
      assert Habits.as_datetime("not a date") == nil
    end
  end

  test "gaps are said out loud, not numbered" do
    assert Habits.ago(0) == "today"
    assert Habits.ago(1) == "yesterday"
    assert Habits.ago(8) == "8 days ago"
  end
end
