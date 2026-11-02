defmodule BotArmyChore.Repo.Migrations.AddArchiveAndCompletionUndo do
  @moduledoc """
  Two columns, both for the same reason: a press with no way back is the wrong shape.

  `tasks.archived_at` is "she stopped doing this one". It is a mark rather than a delete, so
  the row keeps its id, its schedule and its completion history — restoring the same chore
  is not the same as writing a new one that looks like it. Every read filters the mark.

  `chore_completions.next_due_at_before` is what the completion displaced. Undoing a
  completion by recomputing the next due date from the cadence would move the schedule to
  *tonight plus a week*, i.e. it would quietly be a different chore afterwards.
  """
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add_if_not_exists(:archived_at, :utc_datetime_usec)
    end

    alter table(:chore_completions) do
      add_if_not_exists(:next_due_at_before, :utc_datetime_usec)
    end

    create_if_not_exists(index(:tasks, [:tenant_id, :archived_at]))
  end
end
