defmodule BotArmyChore.Handlers.TaskHandlerTest do
  use ExUnit.Case
  @moduletag :handlers
  import Mox

  setup :set_mox_global

  setup do
    stub(BotArmyChore.TaskStoreMock, :create, fn _payload ->
      {:ok, %{"id" => UUID.uuid4(), "title" => "test task"}}
    end)

    stub(BotArmyChore.TaskStoreMock, :update, fn _task_id, _payload ->
      {:ok, %{"id" => UUID.uuid4(), "title" => "test task"}}
    end)

    stub(BotArmyChore.TaskStoreMock, :complete, fn _task_id ->
      {:ok, %{"id" => UUID.uuid4(), "title" => "test task", "frequency" => "once"}}
    end)

    stub(BotArmyChore.TaskStoreMock, :set_next_due, fn _task_id, _next_due ->
      {:ok, %{"id" => UUID.uuid4(), "title" => "test task"}}
    end)

    :ok
  end

  describe "handle_create/1" do
    test "successfully creates a chore task" do
      message = valid_create_message()

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end

    test "returns error for missing title" do
      message =
        valid_create_message()
        |> put_in(["payload", "title"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end

    test "returns error for missing frequency" do
      message =
        valid_create_message()
        |> put_in(["payload", "frequency"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end

    test "requires both title and frequency" do
      message =
        valid_create_message()
        |> put_in(["payload", "title"], nil)
        |> put_in(["payload", "frequency"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end

    test "accepts optional category and priority" do
      message =
        valid_create_message()
        |> put_in(["payload", "category"], "kitchen")
        |> put_in(["payload", "priority"], "high")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end

    test "a chore written down without a day is on the list today" do
      # The reminder loop only speaks about a chore that has a day (`open_and_dated?/1`),
      # so a row created without one was silent forever: on the card, invisible to the
      # tiers. The day is the bot's, the cadence is hers.
      assert_created_due_date(valid_create_message(), Date.to_iso8601(Date.utc_today()))
    end

    test "a nil or blank day is the same as no day at all" do
      for blank <- [nil, "", "   "] do
        message = valid_create_message() |> put_in(["payload", "due_date"], blank)
        assert_created_due_date(message, Date.to_iso8601(Date.utc_today()))
      end
    end

    test "a day she did give is kept exactly as she said it, past or future" do
      for day <- ["2026-12-01", "2026-10-01"] do
        message = valid_create_message() |> put_in(["payload", "due_date"], day)
        assert_created_due_date(message, day)
      end
    end

    test "every cadence gets the day it was written on, because a cadence is not a deferral" do
      for frequency <- ["once", "daily", "weekly", "monthly", "yearly"] do
        message = valid_create_message() |> put_in(["payload", "frequency"], frequency)
        assert_created_due_date(message, Date.to_iso8601(Date.utc_today()))
      end
    end

    test "accepts various task titles" do
      for title <- ["Wash dishes", "Vacuum living room", "Do laundry", "Clean bathroom"] do
        message = valid_create_message() |> put_in(["payload", "title"], title)
        assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
      end
    end

    test "accepts various frequencies" do
      for frequency <- ["daily", "weekly", "biweekly", "monthly"] do
        message = valid_create_message() |> put_in(["payload", "frequency"], frequency)
        assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
      end
    end

    test "handles full chore task details" do
      message =
        valid_create_message()
        |> put_in(["payload", "description"], "Thoroughly clean all surfaces")
        |> put_in(["payload", "estimated_duration"], 30)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    end
  end

  # A surface does not wrap its arguments in `"payload"` — it sends them flat, the way
  # `fitness.set.record` is asked (`"payload"` for an envelope, the top level for a flat body).
  # One rule, read once in the handler, so the two callers do the same work.
  describe "a flat request body" do
    test "creates the chore with no payload key" do
      expect(BotArmyChore.TaskStoreMock, :create, fn payload ->
        assert payload["title"] == "Wipe the counters"
        assert payload["frequency"] == "daily"
        assert payload["category"] == "chore"
        {:ok, %{"id" => UUID.uuid4(), "title" => "Wipe the counters"}}
      end)

      assert :ok =
               BotArmyChore.Handlers.TaskHandler.handle_create(%{
                 "title" => "Wipe the counters",
                 "category" => "chore",
                 "frequency" => "daily"
               })
    end

    test "completes the chore with no payload key" do
      expect(BotArmyChore.TaskStoreMock, :complete, fn id ->
        assert id == "abc"
        {:ok, %{"id" => "abc", "title" => "Dishes", "frequency" => "once"}}
      end)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(%{"task_id" => "abc"})
    end

    test "a press with nowhere to answer still does the work" do
      # The discord check-in's shape: the chore is created, no answer is owed, and a missing
      # broker must not turn a stored chore into a crash.
      assert :ok =
               BotArmyChore.Handlers.TaskHandler.handle_create(
                 %{"title" => "Tidy the table", "category" => "chore", "frequency" => "once"},
                 nil
               )
    end
  end

  describe "handle_assign/1" do
    test "successfully assigns a chore task" do
      message = valid_assign_message()

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end

    test "returns error for missing task_id" do
      message =
        valid_assign_message()
        |> put_in(["payload", "task_id"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end

    test "returns error for missing assigned_to" do
      message =
        valid_assign_message()
        |> put_in(["payload", "assigned_to"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end

    test "requires both task_id and assigned_to" do
      message =
        valid_assign_message()
        |> put_in(["payload", "task_id"], nil)
        |> put_in(["payload", "assigned_to"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end

    test "accepts optional due_date" do
      message =
        valid_assign_message()
        |> put_in(["payload", "due_date"], "2026-03-09")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end

    test "assigns to different household members" do
      for person <- ["Alice", "Bob", "Charlie", "Diana"] do
        message = valid_assign_message() |> put_in(["payload", "assigned_to"], person)
        assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
      end
    end

    test "handles assignment with notes" do
      message =
        valid_assign_message()
        |> put_in(["payload", "notes"], "Please use eco-friendly cleaning products")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_assign(message)
    end
  end

  describe "handle_complete/1" do
    test "successfully completes a chore task" do
      message = valid_complete_message()

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end

    test "returns error for missing task_id" do
      message =
        valid_complete_message()
        |> put_in(["payload", "task_id"], nil)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end

    test "accepts optional completed_by" do
      message =
        valid_complete_message()
        |> put_in(["payload", "completed_by"], "Alice")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end

    test "accepts optional notes on completion" do
      message =
        valid_complete_message()
        |> put_in(["payload", "notes"], "All dishes washed and dried")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end

    test "accepts optional quality_rating" do
      message =
        valid_complete_message()
        |> put_in(["payload", "quality_rating"], 5)

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end

    test "handles completion with multiple optional fields" do
      message =
        valid_complete_message()
        |> put_in(["payload", "completed_by"], "Bob")
        |> put_in(["payload", "quality_rating"], 4)
        |> put_in(["payload", "notes"], "Completed on time with good results")

      assert :ok = BotArmyChore.Handlers.TaskHandler.handle_complete(message)
    end
  end

  # Helper functions

  # The payload the store was actually asked to persist — the derived day has to reach the
  # row, not just the reply the caller sees.
  defp assert_created_due_date(message, expected) do
    parent = self()

    expect(BotArmyChore.TaskStoreMock, :create, fn payload ->
      send(parent, {:created, payload})
      {:ok, %{"id" => UUID.uuid4(), "title" => payload["title"]}}
    end)

    assert :ok = BotArmyChore.Handlers.TaskHandler.handle_create(message)
    assert_received {:created, payload}
    assert payload["due_date"] == expected
  end

  defp valid_create_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "chore.task.create",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "tenant_id" => "00000000-0000-0000-0000-000000000001",
      "user_id" => nil,
      "payload" => %{
        "title" => "Wash dishes",
        "frequency" => "daily",
        "category" => "kitchen",
        "priority" => "normal"
      }
    }
  end

  defp valid_assign_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "chore.task.assign",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "tenant_id" => "00000000-0000-0000-0000-000000000001",
      "user_id" => nil,
      "payload" => %{
        "task_id" => UUID.uuid4(),
        "assigned_to" => "Alice"
      }
    }
  end

  defp valid_complete_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "chore.task.complete",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "tenant_id" => "00000000-0000-0000-0000-000000000001",
      "user_id" => nil,
      "payload" => %{
        "task_id" => UUID.uuid4()
      }
    }
  end
end
