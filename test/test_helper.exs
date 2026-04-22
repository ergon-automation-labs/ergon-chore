ExUnit.configure(exclude: [:integration, :load, :nats_live])
ExUnit.start()

Mox.defmock(BotArmyChore.TaskStoreMock, for: BotArmyChore.TaskStoreBehaviour)
