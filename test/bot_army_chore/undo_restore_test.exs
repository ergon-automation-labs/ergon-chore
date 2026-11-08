defmodule BotArmyChore.UndoRestoreTest do
  use ExUnit.Case

  @moduletag :stores

  alias BotArmyChore.Schemas.ChoreCompletion
  alias BotArmyChore.TaskStore

  defp completion(attrs) do
    struct(
      %ChoreCompletion{},
      Keyword.merge(
        [next_due_at_before: ~U[2026-11-01 21:24:26Z], completed_at_before: nil],
        attrs
      )
    )
  end

  # Measured 2026-11-08: the porch was last swept on 2026-10-25, before `chore_completions`
  # existed. Taking the press back found no remaining row, so the undo wrote
  # `completed_at: nil` and the card said "not done yet" about a porch she had swept a week
  # earlier. The displaced date is in the completion row; the undo has to use it.
  test "the displaced completion date comes back even when no history row remains" do
    last = completion(completed_at_before: ~U[2026-10-25 21:24:26Z])

    attrs = TaskStore.undo_attrs(last, nil)

    assert attrs["completed_at"] == ~N[2026-10-25 21:24:26]
    assert attrs["status"] == "completed"
  end

  test "the schedule restored is the one the press displaced, never a recomputed one" do
    last = completion(next_due_at_before: ~U[2026-11-01 21:24:26.641913Z])

    assert TaskStore.undo_attrs(last, nil)["next_due_at"] == ~U[2026-11-01 21:24:26.641913Z]
  end

  test "history written before the column existed falls back to the remaining row" do
    last = completion(completed_at_before: nil)
    previous = completion(completed_at: ~U[2026-10-20 08:00:00Z])

    attrs = TaskStore.undo_attrs(last, previous)

    assert attrs["completed_at"] == ~N[2026-10-20 08:00:00]
    assert attrs["status"] == "completed"
  end

  # The bug the first undo shipped with: a recurring chore with nothing left in its history
  # must not read `completed`, or it leaves the reminder loop for a chore she never did.
  test "nothing left to restore goes back to pending" do
    attrs = TaskStore.undo_attrs(completion(completed_at_before: nil), nil)

    assert attrs["completed_at"] == nil
    assert attrs["status"] == "pending"
  end

  test "a displaced date wins over the remaining row, because it is what the row held" do
    last = completion(completed_at_before: ~U[2026-10-25 21:24:26Z])
    previous = completion(completed_at: ~U[2026-09-01 08:00:00Z])

    assert TaskStore.undo_attrs(last, previous)["completed_at"] == ~N[2026-10-25 21:24:26]
  end
end
