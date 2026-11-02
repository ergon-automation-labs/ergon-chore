defmodule BotArmyChore.RepeatPressTest do
  @moduledoc """
  One chore, one occasion — even when one press arrives twice.

  The handheld's write budget is 20 s because the chore bot's database can be reconnecting,
  so a press that looks like it failed may well have been counted. Pressing again is the
  natural thing to do, and the cost of treating it as a second occasion is not cosmetic: a
  weekly chore moves a second week forward, and the derived habit counts two occasions where
  she did the work once.
  """
  use ExUnit.Case, async: true
  @moduletag :stores

  alias BotArmyChore.TaskStore

  @now ~U[2026-11-02 18:00:00Z]

  defp task(completed_at), do: %{"id" => "t", "completed_at" => completed_at}

  test "a press a few seconds after the first is the same press" do
    assert TaskStore.recently_completed?(task("2026-11-02T17:59:50Z"), @now)
  end

  test "a press inside the window is still the same press, one second outside it is not" do
    assert TaskStore.recently_completed?(task("2026-11-02T17:58:01Z"), @now)
    refute TaskStore.recently_completed?(task("2026-11-02T17:57:59Z"), @now)
  end

  test "a chore completed this morning can be done again this evening" do
    refute TaskStore.recently_completed?(task("2026-11-02T08:00:00Z"), @now)
  end

  test "a chore with no completion recorded is never a repeat" do
    refute TaskStore.recently_completed?(task(nil), @now)
  end

  test "a timestamp that will not parse does not block a real completion" do
    refute TaskStore.recently_completed?(task("not a date"), @now)
    refute TaskStore.recently_completed?(%{"id" => "t"}, @now)
  end
end
