defmodule BotArmyChoreTest do
  use ExUnit.Case
  @moduletag :core
  doctest BotArmyChore

  test "version" do
    assert BotArmyChore.version() == "0.1.0"
  end
end
