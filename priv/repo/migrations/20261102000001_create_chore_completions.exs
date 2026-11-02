defmodule BotArmyChore.Repo.Migrations.CreateChoreCompletions do
  @moduledoc """
  One row per completion. A record, not a counter.

  `tasks.completed_at` is *overwritten* every time a recurring chore is finished, so the
  row can say when it was last done and never how often — which makes "three of the last
  four weeks" unanswerable, and any number printed in its place invented. This table is
  the history that makes the question answerable.

  No foreign key: a chore that is deleted leaves its completions behind, and the habit
  read joins to `tasks` so an orphaned row is invisible rather than resurrecting a habit
  for a chore that no longer exists.
  """
  use Ecto.Migration

  def change do
    create_if_not_exists table(:chore_completions, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:task_id, :uuid, null: false)
      add(:completed_at, :utc_datetime_usec, null: false)
      add(:tenant_id, :uuid, null: false)
      add(:user_id, :uuid)

      timestamps(type: :utc_datetime_usec)
    end

    # The habit query is "this chore, since this instant" — the leading column is the
    # chore, and the second is the range.
    create_if_not_exists(index(:chore_completions, [:task_id, :completed_at]))
    create_if_not_exists(index(:chore_completions, [:tenant_id, :completed_at]))
  end
end
