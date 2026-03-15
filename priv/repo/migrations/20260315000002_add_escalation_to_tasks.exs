defmodule BotArmyChore.Repo.Migrations.AddEscalationToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :notification_level, :integer, default: 0
      add :last_notified_at, :utc_datetime_usec
    end

    create index(:tasks, [:notification_level])
  end
end
