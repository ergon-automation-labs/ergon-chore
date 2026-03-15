defmodule BotArmyChore.TaskStoreBehaviour do
  @moduledoc """
  Behaviour for TaskStore to enable mocking in tests.
  """

  @callback create(map) :: {:ok, map} | {:error, term}
  @callback update(binary, map) :: {:ok, map} | {:error, term}
  @callback start(binary) :: {:ok, map} | {:error, term}
  @callback complete(binary) :: {:ok, map} | {:error, term}
  @callback get(binary) :: {:ok, map} | {:error, term}
  @callback list :: [map]
  @callback list_all :: [map]
  @callback list_overdue_recurring :: [map]
  @callback set_next_due(binary, DateTime.t()) :: {:ok, map} | {:error, term}
  @callback set_notification_level(binary, integer, DateTime.t()) :: {:ok, map} | {:error, term}
end
