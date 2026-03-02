defmodule BotArmyChore.Handlers.TaskHandler do
  @moduledoc """
  Handles chore task-related events for the Chore bot.

  This module processes incoming chore task messages:
  - `chore.task.create` - Create a new chore task
  - `chore.task.assign` - Assign chore to household member
  - `chore.task.complete` - Mark chore as complete

  Each operation validates the input and publishes response events.
  """

  require Logger

  @doc """
  Handle chore task creation event.

  Validates the task data and publishes a task.created event.
  """
  def handle_create(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_create_payload(payload) do
      :ok ->
        Logger.info("Chore task created: event_id=#{event_id}")
        publish_event("chore.task.created", payload, event_id)

      {:error, reason} ->
        Logger.warning("Invalid chore task payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid chore task data")
    end
  end

  @doc """
  Handle chore assignment event.

  Validates the assignment data and publishes a task.assigned event.
  """
  def handle_assign(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_assign_payload(payload) do
      :ok ->
        Logger.info("Chore task assigned: event_id=#{event_id}")
        publish_event("chore.task.assigned", payload, event_id)

      {:error, reason} ->
        Logger.warning("Invalid chore assignment payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid assignment data")
    end
  end

  @doc """
  Handle chore completion event.

  Validates the completion data and publishes a task.completed event.
  """
  def handle_complete(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_complete_payload(payload) do
      :ok ->
        Logger.info("Chore task completed: event_id=#{event_id}")
        publish_event("chore.task.completed", payload, event_id)

      {:error, reason} ->
        Logger.warning("Invalid chore completion payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid completion data")
    end
  end

  # Private functions

  defp validate_create_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "title"),
         :ok <- require_field(payload, "frequency") do
      :ok
    end
  end

  defp validate_create_payload(_), do: {:error, :invalid_payload}

  defp validate_assign_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "task_id"),
         :ok <- require_field(payload, "assigned_to") do
      :ok
    end
  end

  defp validate_assign_payload(_), do: {:error, :invalid_payload}

  defp validate_complete_payload(payload) when is_map(payload) do
    require_field(payload, "task_id")
  end

  defp validate_complete_payload(_), do: {:error, :invalid_payload}

  defp require_field(payload, field) do
    case payload do
      %{^field => value} when value not in [nil, ""] -> :ok
      _ -> {:error, {:missing_field, field}}
    end
  end

  defp publish_event(event_type, payload, event_id) do
    event_data = %{
      "event" => event_type,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_chore",
      "source_node" => get_node_name(),
      "triggered_by" => "chore.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "task_id" => Map.get(payload, "task_id"),
        "title" => Map.get(payload, "title"),
        "frequency" => Map.get(payload, "frequency"),
        "assigned_to" => Map.get(payload, "assigned_to"),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyChore.NATS.Publisher.publish(event_data) do
      :ok -> Logger.debug("Published event: #{event_type}")
      {:error, reason} -> Logger.error("Failed to publish event: #{inspect(reason)}")
    end
  end

  defp publish_error(event_id, reason, message) do
    error_event = %{
      "event" => "chore.error",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_chore",
      "source_node" => get_node_name(),
      "triggered_by" => "chore.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "error" => message,
        "reason" => inspect(reason),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyChore.NATS.Publisher.publish(error_event) do
      :ok -> Logger.debug("Published error event")
      {:error, err} -> Logger.error("Failed to publish error: #{inspect(err)}")
    end
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end
end
