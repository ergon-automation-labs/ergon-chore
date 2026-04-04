defmodule BotArmyChore.TaskStoreBehaviour do
  @moduledoc """
  Behaviour for TaskStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback start(binary) :: {:ok, map} | {:error, term}
  @callback complete(binary) :: {:ok, map} | {:error, term}
  @callback get(binary, binary) :: {:ok, map} | {:error, term}
  @callback list(binary) :: [map]
  @callback list_all(binary) :: [map]
  @callback list_overdue_recurring(binary) :: [map]
  @callback set_next_due(binary, DateTime.t()) :: {:ok, map} | {:error, term}
  @callback set_notification_level(binary, integer, DateTime.t()) :: {:ok, map} | {:error, term}
end
