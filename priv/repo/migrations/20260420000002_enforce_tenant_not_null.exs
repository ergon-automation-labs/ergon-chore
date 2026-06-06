defmodule BotArmyChore.Repo.Migrations.EnforceTenantAndUserIdNotNull do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE tasks ALTER COLUMN tenant_id SET NOT NULL")
    execute("ALTER TABLE tasks ALTER COLUMN user_id SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE tasks ALTER COLUMN tenant_id DROP NOT NULL")
    execute("ALTER TABLE tasks ALTER COLUMN user_id DROP NOT NULL")
  end
end
