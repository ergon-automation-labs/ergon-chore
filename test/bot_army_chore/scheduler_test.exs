defmodule BotArmyChore.SchedulerTest do
  use ExUnit.Case
  @moduletag :core
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  defp task(attrs) do
    Map.merge(
      %{
        "id" => UUID.uuid4(),
        "title" => "Cleaning routine",
        "status" => "pending",
        "due_date" => nil,
        "frequency" => "weekly"
      },
      attrs
    )
  end

  describe "check_overdue_tasks/0" do
    test "counts only open chores, by days past their due date" do
      today = Date.utc_today()

      expect(BotArmyChore.TaskStoreMock, :list_all, fn _tenant ->
        {:ok,
         [
           task(%{"due_date" => Date.to_iso8601(Date.add(today, -4))}),
           task(%{"due_date" => Date.to_iso8601(today)}),
           task(%{"due_date" => Date.to_iso8601(Date.add(today, 3))}),
           task(%{"due_date" => Date.to_iso8601(Date.add(today, -9)), "status" => "completed"}),
           task(%{"due_date" => nil})
         ]}
      end)

      # due 4 days ago is overdue; due today and due next week are not, and the
      # completed one is not reminded about at all.
      assert [{_id, 4}] = BotArmyChore.Scheduler.check_overdue_tasks()
    end

    test "a completed chore is never reminded about, however old its due date" do
      expect(BotArmyChore.TaskStoreMock, :list_all, fn _tenant ->
        {:ok,
         [
           task(%{
             "due_date" => Date.to_iso8601(Date.add(Date.utc_today(), -30)),
             "status" => "completed"
           })
         ]}
      end)

      assert [] = BotArmyChore.Scheduler.check_overdue_tasks()
    end

    test "a store that cannot be read is an empty reminder list, not a crash" do
      expect(BotArmyChore.TaskStoreMock, :list_all, fn _tenant ->
        {:error, :database_unavailable}
      end)

      assert [] = BotArmyChore.Scheduler.check_overdue_tasks()
    end

    test "a store that raises is an empty reminder list, not a crash" do
      expect(BotArmyChore.TaskStoreMock, :list_all, fn _tenant -> raise "boom" end)

      assert [] = BotArmyChore.Scheduler.check_overdue_tasks()
    end

    test "a due date the store sends in a shape it cannot parse is not counted as overdue" do
      expect(BotArmyChore.TaskStoreMock, :list_all, fn _tenant ->
        {:ok, [task(%{"due_date" => "not-a-date"})]}
      end)

      assert [] = BotArmyChore.Scheduler.check_overdue_tasks()
    end
  end
end
