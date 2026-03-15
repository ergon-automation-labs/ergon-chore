defmodule BotArmyChore.TaskStoreBehaviour do
  @moduledoc """
  Behaviour for TaskStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback start(binary) :: {:ok, map} | {:error, term}
  @callback complete(binary) :: {:ok, map} | {:error, term}
  @callback get(binary) :: map | nil
  @callback list :: [map]
  @callback list_all :: [map]
end
