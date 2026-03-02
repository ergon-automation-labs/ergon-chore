defmodule BotArmyChore.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :category, :string, null: false
      add :frequency, :string
      add :assigned_to, :string
      add :priority, :string, default: "normal", null: false
      add :due_date, :date
      add :status, :string, default: "pending", null: false
      add :location, :string
      add :completed_at, :naive_datetime

      timestamps()
    end

    create index(:tasks, [:status])
    create index(:tasks, [:priority])
    create index(:tasks, [:assigned_to])
    create index(:tasks, [:category])
    create index(:tasks, [:due_date])
  end
end
