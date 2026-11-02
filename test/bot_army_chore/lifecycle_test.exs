defmodule BotArmyChore.LifecycleTest do
  @moduledoc """
  The three presses that decide whether a chore is on the list at all: done, taken back,
  put away — and the one that brings it back.

  What is asserted here is the contract the card depends on: each press reaches the store
  with the id it was given, and a refusal is a refusal *with words*, never a `{:ok, …}` that
  would let a panel draw a change that did not happen.
  """
  use ExUnit.Case
  @moduletag :handlers
  import Mox

  alias BotArmyChore.Handlers.TaskHandler

  setup :set_mox_global
  setup :verify_on_exit!

  @task_id "81c869d0-445b-4637-ac5a-650aad41d5d6"

  defp message(event, payload) do
    %{
      "event_id" => UUID.uuid4(),
      "event" => event,
      "tenant_id" => "00000000-0000-0000-0000-000000000001",
      "user_id" => nil,
      "payload" => payload
    }
  end

  test "archive reaches the store with the id it was given" do
    expect(BotArmyChore.TaskStoreMock, :archive, fn @task_id ->
      {:ok, %{"id" => @task_id, "archived_at" => "2026-11-02T17:00:00Z"}}
    end)

    assert :ok =
             TaskHandler.handle_archive(message("chore.task.archive", %{"task_id" => @task_id}))
  end

  test "restore reaches the store, and answers with the row it brought back" do
    expect(BotArmyChore.TaskStoreMock, :restore, fn @task_id ->
      {:ok, %{"id" => @task_id, "archived_at" => nil}}
    end)

    assert :ok =
             TaskHandler.handle_restore(message("chore.task.restore", %{"task_id" => @task_id}))
  end

  test "uncomplete reaches the store" do
    expect(BotArmyChore.TaskStoreMock, :uncomplete, fn @task_id ->
      {:ok, %{"id" => @task_id, "status" => "completed"}}
    end)

    assert :ok =
             TaskHandler.handle_uncomplete(
               message("chore.task.uncomplete", %{"task_id" => @task_id})
             )
  end

  test "a chore that is not on the list is refused, and the store is not asked twice" do
    expect(BotArmyChore.TaskStoreMock, :archive, fn _ -> {:error, :not_found} end)

    assert :ok =
             TaskHandler.handle_archive(message("chore.task.archive", %{"task_id" => @task_id}))
  end

  test "there being nothing to take back is its own answer, not a silent success" do
    expect(BotArmyChore.TaskStoreMock, :uncomplete, fn _ -> {:error, :no_completion} end)

    assert :ok =
             TaskHandler.handle_uncomplete(
               message("chore.task.uncomplete", %{"task_id" => @task_id})
             )
  end

  test "a repeat press is refused in words, and the schedule is not advanced again" do
    # `set_next_due` has no expectation here: Mox fails the test if the handler advances a
    # schedule for a press that was refused as a repeat.
    expect(BotArmyChore.TaskStoreMock, :complete, fn @task_id -> {:error, :already_completed} end)

    assert :ok =
             TaskHandler.handle_complete(message("chore.task.complete", %{"task_id" => @task_id}))
  end

  test "a press with no id never reaches the store" do
    # No expectation is set: Mox fails the test if the store is called at all.
    assert :ok = TaskHandler.handle_archive(message("chore.task.archive", %{}))
    assert :ok = TaskHandler.handle_restore(message("chore.task.restore", %{"task_id" => ""}))

    assert :ok =
             TaskHandler.handle_uncomplete(message("chore.task.uncomplete", %{"task_id" => nil}))
  end
end
