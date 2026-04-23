defmodule BotArmyChore.Repo.Migrations.AddTenantAndUserId do
  use Ecto.Migration

  def up do
    default_tenant_id = "00000000-0000-0000-0000-000000000001"

    # Add tenant_id and user_id to tasks (idempotent)
    if not Ecto.Migration.column_exists?(:tasks, :tenant_id) do
      alter table(:tasks) do
        add(:tenant_id, :uuid, null: true)
        add(:user_id, :uuid, null: true)
      end

      create(index(:tasks, [:tenant_id]))
      create(index(:tasks, [:user_id]))
      execute("UPDATE tasks SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL")
    end
  end

  def down do
    # Drop indexes and columns for tasks
    drop(index(:tasks, [:tenant_id]))
    drop(index(:tasks, [:user_id]))

    alter table(:tasks) do
      remove(:tenant_id)
      remove(:user_id)
    end
  end
end
