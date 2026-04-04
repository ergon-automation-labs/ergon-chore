defmodule BotArmyChore.Repo.Migrations.AddTenantAndUserId do
  use Ecto.Migration

  def up do
    # tasks table
    alter table(:tasks) do
      add :tenant_id, :uuid, null: true
      add :user_id, :uuid, null: true
    end
    create index(:tasks, [:tenant_id])
    create index(:tasks, [:user_id])

    # Backfill all rows with default tenant UUID
    default_tenant_id = "00000000-0000-0000-0000-000000000001"
    execute("""
    UPDATE tasks SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL
    """)
  end

  def down do
    # tasks table
    drop index(:tasks, [:tenant_id])
    drop index(:tasks, [:user_id])
    alter table(:tasks) do
      remove :tenant_id
      remove :user_id
    end
  end
end
