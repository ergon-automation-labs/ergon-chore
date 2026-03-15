defmodule BotArmyChore.Repo.Migrations.AddSchedulingToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :next_due_at, :utc_datetime_usec
      add :last_completed_at, :utc_datetime_usec
    end

    create index(:tasks, [:next_due_at])
  end
end
