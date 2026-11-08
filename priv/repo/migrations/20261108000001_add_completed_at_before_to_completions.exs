defmodule BotArmyChore.Repo.Migrations.AddCompletedAtBeforeToCompletions do
  @moduledoc """
  The undo had one field of memory too few.

  `next_due_at_before` let it put the *schedule* back, and the status was derived from the
  newest completion row that remained. That works only while every completion has a row.
  Measured 2026-11-08: the porch was last swept on 2026-10-25, which is before this table
  existed, so taking the press back found no row to fall back on and wrote `completed_at:
  nil` — the card then said "not done yet" about a porch she had swept a week earlier, and
  the habit phrasing lost an occasion that really happened.

  So the row now carries the fact it displaced, the same way it carries the date it
  displaced. A null means "written before this column existed", and the reader falls back
  to the remaining history.
  """
  use Ecto.Migration

  def change do
    alter table(:chore_completions) do
      add_if_not_exists(:completed_at_before, :utc_datetime_usec)
    end
  end
end
