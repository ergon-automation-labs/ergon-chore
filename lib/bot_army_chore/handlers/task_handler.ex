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
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)

    # Stamp context into payload
    stamped_payload = Map.merge(payload, %{
      "tenant_id" => tenant_id,
      "user_id" => user_id
    })

    case validate_create_payload(stamped_payload) do
      :ok ->
        case task_store().create(stamped_payload) do
          {:ok, task} ->
            Logger.info("Chore task created: event_id=#{event_id}, task_id=#{task["id"]}")
            publish_event("chore.task.created", Map.put(stamped_payload, "task_id", task["id"]), event_id, tenant_id, user_id)

          {:error, reason} ->
            Logger.warning("Failed to persist chore task: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to persist chore task", tenant_id, user_id)
        end

      {:error, reason} ->
        Logger.warning("Invalid chore task payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid chore task data", tenant_id, user_id)
    end
  end

  @doc """
  Handle chore assignment event.

  Validates the assignment data and publishes a task.assigned event.
  """
  def handle_assign(message) do
    event_id = message["event_id"]
    payload = message["payload"]
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)

    case validate_assign_payload(payload) do
      :ok ->
        case task_store().update(payload["task_id"], %{"assigned_to" => payload["assigned_to"]}) do
          {:ok, _task} ->
            Logger.info("Chore task assigned: event_id=#{event_id}, task_id=#{payload["task_id"]}")
            publish_event("chore.task.assigned", payload, event_id, tenant_id, user_id)

          {:error, :not_found} ->
            Logger.warning("Task not found: #{payload["task_id"]}")
            publish_error(event_id, :not_found, "Task not found", tenant_id, user_id)

          {:error, reason} ->
            Logger.warning("Failed to assign task: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to assign task", tenant_id, user_id)
        end

      {:error, reason} ->
        Logger.warning("Invalid chore assignment payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid assignment data", tenant_id, user_id)
    end
  end

  @doc """
  Handle chore assignment rotation event.

  Rotates the assignment to the next household member and updates the task.
  """
  def handle_rotate(message) do
    event_id = message["event_id"]
    payload = message["payload"]
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)

    case validate_rotate_payload(payload) do
      :ok ->
        task_id = payload["task_id"]

        case rotate_assignment(tenant_id, task_id) do
          {:ok, next_person} ->
            Logger.info("Chore rotated: event_id=#{event_id}, task_id=#{task_id}, assigned_to=#{next_person}")
            publish_event("chore.task.assigned", %{"task_id" => task_id, "assigned_to" => next_person}, event_id, tenant_id, user_id)

          {:error, reason} ->
            Logger.warning("Failed to rotate assignment: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to rotate assignment", tenant_id, user_id)
        end

      {:error, reason} ->
        Logger.warning("Invalid rotation payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid rotation data", tenant_id, user_id)
    end
  end

  @doc """
  Handle chore completion event.

  Validates the completion data and publishes a task.completed event.
  """
  def handle_complete(message) do
    event_id = message["event_id"]
    payload = message["payload"]
    %{tenant_id: tenant_id, user_id: user_id} = BotArmyCore.Tenant.extract_context(message)

    case validate_complete_payload(payload) do
      :ok ->
        case task_store().complete(payload["task_id"]) do
          {:ok, task} ->
            Logger.info("Chore task completed: event_id=#{event_id}, task_id=#{payload["task_id"]}")
            advance_recurring_task(tenant_id, task)
            publish_event("chore.task.completed", payload, event_id, tenant_id, user_id)

          {:error, :not_found} ->
            Logger.warning("Task not found: #{payload["task_id"]}")
            publish_error(event_id, :not_found, "Task not found", tenant_id, user_id)

          {:error, reason} ->
            Logger.warning("Failed to complete task: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to complete task", tenant_id, user_id)
        end

      {:error, reason} ->
        Logger.warning("Invalid chore completion payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid completion data", tenant_id, user_id)
    end
  end

  # Private functions

  defp validate_create_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "title"),
         :ok <- require_field(payload, "frequency"),
         :ok <- require_field(payload, "category") do
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

  defp validate_rotate_payload(payload) when is_map(payload) do
    require_field(payload, "task_id")
  end

  defp validate_rotate_payload(_), do: {:error, :invalid_payload}

  defp rotate_assignment(tenant_id, task_id) do
    members = Application.get_env(:bot_army_chore, :household_members, [])

    case BotArmyChore.TaskStore.get(tenant_id, task_id) do
      {:ok, task} ->
        current_person = task["assigned_to"]
        next_person = get_next_member(current_person, members)

        case BotArmyChore.TaskStore.update(task_id, %{"assigned_to" => next_person}) do
          {:ok, _} -> {:ok, next_person}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_next_member(current, members) when is_list(members) and length(members) > 0 do
    case Enum.find_index(members, &(&1 == current)) do
      nil -> List.first(members)
      idx -> Enum.at(members, rem(idx + 1, length(members)))
    end
  end

  defp get_next_member(_, _), do: nil

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

  defp publish_event(event_type, payload, event_id, tenant_id, user_id) do
    event_data = %{
      "event" => event_type,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_chore",
      "source_node" => get_node_name(),
      "triggered_by" => "chore.bot",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
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

  defp publish_error(event_id, reason, message, tenant_id, user_id) do
    error_event = %{
      "event" => "chore.error",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_chore",
      "source_node" => get_node_name(),
      "triggered_by" => "chore.bot",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id,
      "user_id" => user_id,
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

  defp advance_recurring_task(_tenant_id, %{"frequency" => freq, "id" => id}) when freq not in [nil, "once"] do
    task_store().set_next_due(id, compute_next_due(freq))
  end

  defp advance_recurring_task(_tenant_id, _), do: :ok

  defp compute_next_due("daily"),   do: DateTime.add(DateTime.utc_now(), 1, :day)
  defp compute_next_due("weekly"),  do: DateTime.add(DateTime.utc_now(), 7, :day)
  defp compute_next_due("monthly"), do: DateTime.add(DateTime.utc_now(), 30, :day)
  defp compute_next_due("yearly"),  do: DateTime.add(DateTime.utc_now(), 365, :day)
  defp compute_next_due(_),         do: DateTime.add(DateTime.utc_now(), 7, :day)

  defp task_store, do: Application.get_env(:bot_army_chore, :task_store, BotArmyChore.TaskStore)
end
