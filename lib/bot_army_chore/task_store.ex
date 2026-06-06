defmodule BotArmyChore.TaskStore do
  @moduledoc """
  In-memory task storage for the Chore bot.

  This GenServer maintains the in-memory state of all chore tasks while Ecto handles
  persistence to PostgreSQL. On init, it loads all tasks from the database.
  Every mutation (create, update, start, complete) is persisted to the database before updating state.

  ## API

  - `create/1` - Create a new chore task
  - `update/2` - Update an existing task
  - `start/1` - Mark a task as in_progress
  - `complete/1` - Mark a task as completed
  - `get/1` - Retrieve a task by ID
  - `list/0` - List all pending and in_progress tasks
  - `list_all/0` - List all tasks including completed
  """

  @behaviour BotArmyChore.TaskStoreBehaviour

  use GenServer
  require Logger

  @server __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @doc """
  Create a new chore task from payload.

  Returns `{:ok, task}` with the created task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def create(payload) when is_map(payload) do
    GenServer.call(@server, {:create, payload})
  end

  @doc """
  Update an existing task.

  Returns `{:ok, task}` with the updated task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def update(task_id, payload) when is_binary(task_id) and is_map(payload) do
    GenServer.call(@server, {:update, task_id, payload})
  end

  @doc """
  Start a task (mark as in_progress).

  Returns `{:ok, task}` with the updated task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def start(task_id) when is_binary(task_id) do
    GenServer.call(@server, {:start, task_id})
  end

  @doc """
  Complete a task.

  Returns `{:ok, task}` with the completed task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def complete(task_id) when is_binary(task_id) do
    GenServer.call(@server, {:complete, task_id})
  end

  @doc """
  Retrieve a task by ID, scoped to a tenant.

  Returns `{:ok, task}` or `{:error, :not_found}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def get(tenant_id, task_id) when is_binary(tenant_id) and is_binary(task_id) do
    GenServer.call(@server, {:get, tenant_id, task_id})
  end

  @doc """
  List all pending and in_progress tasks for a tenant.

  Returns `{:ok, tasks}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def list(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list, tenant_id})
  end

  @doc """
  List all tasks including completed for a tenant.

  Returns `{:ok, tasks}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def list_all(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list_all, tenant_id})
  end

  @doc """
  Clear all tasks (for testing).

  Returns `:ok`.
  """
  def clear do
    GenServer.call(@server, :clear)
  end

  @doc """
  List all recurring tasks that are overdue for a tenant.

  Returns list of tasks with frequency != "once" and next_due_at <= now.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def list_overdue_recurring(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list_overdue_recurring, tenant_id})
  end

  @doc """
  Set the next due date for a recurring task.

  Returns `{:ok, task}` with the updated task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def set_next_due(task_id, next_due_at)
      when is_binary(task_id) and is_struct(next_due_at, DateTime) do
    GenServer.call(@server, {:set_next_due, task_id, next_due_at})
  end

  @doc """
  Set the notification level for a task.

  Returns `{:ok, task}` with the updated task, or `{:error, reason}`.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def set_notification_level(task_id, level, notified_at \\ DateTime.utc_now())
      when is_binary(task_id) and is_integer(level) and is_struct(notified_at, DateTime) do
    GenServer.call(@server, {:set_notification_level, task_id, level, notified_at})
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Logger.info("TaskStore started")
    # Load all tasks from database into GenServer state
    # Gracefully handle database unavailability (e.g., in tests)
    state =
      try do
        tasks = BotArmyChore.Repo.all(BotArmyChore.Schemas.Task)

        Enum.reduce(tasks, %{}, fn task, acc ->
          Map.put(acc, task.id |> to_string(), schema_to_map(task))
        end)
      rescue
        _ ->
          Logger.warning(
            "Could not load tasks from database (database unavailable). Starting with empty state."
          )

          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    task_id = Ecto.UUID.generate()

    # Parse due_date if present
    due_date =
      case Map.get(payload, "due_date") do
        nil ->
          nil

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            {:error, _} -> nil
          end

        _ ->
          nil
      end

    changeset =
      BotArmyChore.Schemas.Task.changeset(
        %BotArmyChore.Schemas.Task{id: task_id},
        %{
          "tenant_id" => payload["tenant_id"],
          "user_id" => Map.get(payload, "user_id"),
          "title" => payload["title"],
          "category" => payload["category"],
          "frequency" => Map.get(payload, "frequency", "once"),
          "assigned_to" => Map.get(payload, "assigned_to"),
          "priority" => Map.get(payload, "priority", "normal"),
          "due_date" => due_date,
          "location" => Map.get(payload, "location"),
          "status" => "pending"
        }
      )

    case BotArmyChore.Repo.insert(changeset) do
      {:ok, db_task} ->
        task = schema_to_map(db_task)
        new_state = Map.put(state, task_id, task)
        Logger.info("Created chore task in database: #{task_id}")
        {:reply, {:ok, task}, new_state}

      {:error, changeset} ->
        Logger.error("Failed to create task: #{inspect(changeset.errors)}")
        {:reply, {:error, :database_error}, state}
    end
  end

  @impl true
  def handle_call({:update, task_id, payload}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _task ->
        task_uuid = Ecto.UUID.cast!(task_id)

        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 # Parse due_date if present
                 due_date =
                   case Map.get(payload, "due_date") do
                     nil ->
                       nil

                     date_str when is_binary(date_str) ->
                       case Date.from_iso8601(date_str) do
                         {:ok, date} -> date
                         {:error, _} -> nil
                       end

                     _ ->
                       nil
                   end

                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{
                       "title" => Map.get(payload, "title", db_task.title),
                       "category" => Map.get(payload, "category", db_task.category),
                       "frequency" => Map.get(payload, "frequency", db_task.frequency),
                       "assigned_to" => Map.get(payload, "assigned_to", db_task.assigned_to),
                       "priority" => Map.get(payload, "priority", db_task.priority),
                       "due_date" => due_date || db_task.due_date,
                       "location" => Map.get(payload, "location", db_task.location)
                     }
                   )

                 case BotArmyChore.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                 end
               else
                 BotArmyChore.Repo.rollback(:not_found)
               end
             end) do
          {:ok, updated_db_task} ->
            updated_task = schema_to_map(updated_db_task)
            new_state = Map.put(state, task_id, updated_task)
            Logger.info("Updated chore task in database: #{task_id}")
            {:reply, {:ok, updated_task}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to update task: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:start, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _task ->
        task_uuid = Ecto.UUID.cast!(task_id)

        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{"status" => "in_progress"}
                   )

                 case BotArmyChore.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                 end
               else
                 BotArmyChore.Repo.rollback(:not_found)
               end
             end) do
          {:ok, started_db_task} ->
            started_task = schema_to_map(started_db_task)
            new_state = Map.put(state, task_id, started_task)
            Logger.info("Started chore task in database: #{task_id}")
            {:reply, {:ok, started_task}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to start task: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:complete, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _task ->
        task_uuid = Ecto.UUID.cast!(task_id)

        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{
                       "status" => "completed",
                       "completed_at" =>
                         NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
                     }
                   )

                 case BotArmyChore.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                 end
               else
                 BotArmyChore.Repo.rollback(:not_found)
               end
             end) do
          {:ok, completed_db_task} ->
            completed_task = schema_to_map(completed_db_task)
            new_state = Map.put(state, task_id, completed_task)
            Logger.info("Completed chore task in database: #{task_id}")
            {:reply, {:ok, completed_task}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to complete task: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:get, tenant_id, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      task ->
        if task["tenant_id"] == tenant_id do
          {:reply, {:ok, task}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:list, tenant_id}, _from, state) do
    tasks =
      state
      |> Map.values()
      |> Enum.filter(fn t ->
        t["tenant_id"] == tenant_id && t["status"] in ["pending", "in_progress"]
      end)

    {:reply, {:ok, tasks}, state}
  end

  @impl true
  def handle_call({:list_all, tenant_id}, _from, state) do
    tasks =
      state
      |> Map.values()
      |> Enum.filter(fn t -> t["tenant_id"] == tenant_id end)

    {:reply, {:ok, tasks}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.debug("Clearing all chore tasks")
    {:reply, :ok, %{}}
  end

  @impl true
  def handle_call({:list_overdue_recurring, tenant_id}, _from, state) do
    now = DateTime.utc_now()

    tasks =
      state
      |> Map.values()
      |> Enum.filter(fn t ->
        t["tenant_id"] == tenant_id &&
          t["frequency"] != "once" &&
          t["next_due_at"] != nil &&
          case DateTime.from_iso8601(t["next_due_at"]) do
            {:ok, due_dt, _} -> DateTime.compare(due_dt, now) != :gt
            _ -> false
          end
      end)

    {:reply, tasks, state}
  end

  @impl true
  def handle_call({:set_next_due, task_id, next_due_at}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _task ->
        task_uuid = Ecto.UUID.cast!(task_id)

        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{"next_due_at" => next_due_at}
                   )

                 case BotArmyChore.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                 end
               else
                 BotArmyChore.Repo.rollback(:not_found)
               end
             end) do
          {:ok, updated_db_task} ->
            updated_task = schema_to_map(updated_db_task)
            new_state = Map.put(state, task_id, updated_task)
            Logger.info("Updated next_due_at for task: #{task_id}")
            {:reply, {:ok, updated_task}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to set next_due_at: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:set_notification_level, task_id, level, notified_at}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _task ->
        task_uuid = Ecto.UUID.cast!(task_id)

        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{"notification_level" => level, "last_notified_at" => notified_at}
                   )

                 case BotArmyChore.Repo.update(changeset) do
                   {:ok, updated} -> updated
                   {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                 end
               else
                 BotArmyChore.Repo.rollback(:not_found)
               end
             end) do
          {:ok, updated_db_task} ->
            updated_task = schema_to_map(updated_db_task)
            new_state = Map.put(state, task_id, updated_task)
            Logger.info("Updated notification_level for task: #{task_id}")
            {:reply, {:ok, updated_task}, new_state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:error, changeset} ->
            Logger.error("Failed to set notification_level: #{inspect(changeset.errors)}")
            {:reply, {:error, :database_error}, state}
        end
    end
  end

  # Helper function to convert Ecto schema to map for GenServer state
  defp schema_to_map(%BotArmyChore.Schemas.Task{} = task) do
    %{
      "id" => Ecto.UUID.cast!(task.id) |> to_string(),
      "tenant_id" => task.tenant_id |> to_string(),
      "user_id" => if(task.user_id, do: task.user_id |> to_string(), else: nil),
      "title" => task.title,
      "category" => task.category,
      "frequency" => task.frequency,
      "assigned_to" => task.assigned_to,
      "priority" => task.priority,
      "due_date" => if(task.due_date, do: task.due_date |> to_string(), else: nil),
      "location" => task.location,
      "status" => task.status,
      "completed_at" =>
        if(task.completed_at, do: task.completed_at |> NaiveDateTime.to_iso8601(), else: nil),
      "next_due_at" =>
        if(task.next_due_at, do: task.next_due_at |> DateTime.to_iso8601(), else: nil),
      "last_completed_at" =>
        if(task.last_completed_at, do: task.last_completed_at |> DateTime.to_iso8601(), else: nil),
      "notification_level" => task.notification_level || 0,
      "last_notified_at" =>
        if(task.last_notified_at, do: task.last_notified_at |> DateTime.to_iso8601(), else: nil),
      "created_at" => task.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => task.updated_at |> NaiveDateTime.to_iso8601()
    }
  end
end
