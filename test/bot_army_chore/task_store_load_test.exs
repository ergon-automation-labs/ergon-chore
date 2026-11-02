defmodule BotArmyChore.TaskStoreLoadTest do
  use ExUnit.Case, async: true
  @moduletag :stores

  alias BotArmyChore.Schemas.Task
  alias BotArmyChore.TaskStore

  # Pins the boot race that shipped on 2026-11-02: the store read its state once, from
  # `init`, while Postgrex was still connecting; the rescue made that an empty state and the
  # bot then answered "nothing to do" for thirteen chores that were in Postgres all along.
  defp task(title) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Task{
      id: Ecto.UUID.generate(),
      title: title,
      status: "pending",
      frequency: "weekly",
      tenant_id: BotArmyLibraryCore.Tenant.default_tenant_id(),
      inserted_at: now,
      updated_at: now
    }
  end

  test "a read that fails is retried, and the state is what the retry found" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    loader = fn ->
      n = Agent.get_and_update(calls, fn n -> {n, n + 1} end)

      case n do
        0 -> {:error, :econnrefused}
        1 -> {:error, :econnrefused}
        _ -> {:ok, [task("Sweep the steps")]}
      end
    end

    {:ok, state} = TaskStore.load_tasks(5, loader, fn _ms -> :ok end)

    assert map_size(state) == 1
    assert [{_id, %{"title" => "Sweep the steps"}}] = Map.to_list(state)
    assert Agent.get(calls, & &1) == 3
  end

  test "running out of attempts is an error, never an empty house" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    sleeps = Agent.start_link(fn -> 0 end) |> elem(1)

    loader = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :econnrefused}
    end

    sleep_fun = fn _ms -> Agent.update(sleeps, &(&1 + 1)) end

    assert {:error, :econnrefused} = TaskStore.load_tasks(3, loader, sleep_fun)
    assert Agent.get(calls, & &1) == 3
    assert Agent.get(sleeps, & &1) == 2
  end

  test "an empty database is a successful read, and is allowed" do
    assert {:ok, %{}} = TaskStore.load_tasks(3, fn -> {:ok, []} end, fn _ -> :ok end)
  end
end

defmodule BotArmyChore.ApplicationOrderTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyChore.Application

  # The store reads its state in `init`, so it must start *after* the repo that
  # answers it. The children pipeline prepends, which put it before.
  test "the repo starts before the store that reads from it" do
    children = [
      {:outcome_tracker, []},
      {BotArmyChore.TaskStore, []},
      :some_consumer,
      BotArmyChore.Repo
    ]

    assert [BotArmyChore.Repo, {BotArmyChore.TaskStore, []}, {:outcome_tracker, []}, :some_consumer] =
             Application.storage_first(children)
  end

  test "storage children keep their relative order when there are no others" do
    assert [BotArmyChore.Repo, {BotArmyChore.TaskStore, []}] ==
             Application.storage_first([{BotArmyChore.TaskStore, []}, BotArmyChore.Repo])
  end
end
