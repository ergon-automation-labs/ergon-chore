defmodule BotArmyChore.Handlers.TaskHandlerTest do
  use ExUnit.Case

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

  defp valid_create_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "chore.task.create",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
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
      "payload" => %{
        "task_id" => UUID.uuid4()
      }
    }
  end
end
