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
  Put a chore away — "I stopped doing this one".

  The row is marked, never destroyed: the id, the schedule and the completion history stay,
  so `restore/1` brings back the chore that was put away rather than a lookalike with a new
  id and no past. Every read filters the mark.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def archive(task_id) when is_binary(task_id) do
    GenServer.call(@server, {:archive, task_id})
  end

  @doc """
  Take a chore back out of the drawer. Clears the mark; changes nothing else.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def restore(task_id) when is_binary(task_id) do
    GenServer.call(@server, {:restore, task_id})
  end

  @doc """
  Undo a completion: takes back the last recorded occasion and the schedule it displaced.

  Answers `{:error, :no_completion}` when there is nothing to undo — a press that reports
  success without having changed anything is the same lie as one that reports failure after
  doing the work.
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def uncomplete(task_id) when is_binary(task_id) do
    GenServer.call(@server, {:uncomplete, task_id})
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
  Every recorded completion for a tenant since `since`, oldest first.

  This is the read a habit's count is built on. It answers `{:error, reason}` rather than
  an empty list when the store cannot be read, so a surface can say "I could not find out"
  instead of drawing "never done".
  """
  @impl BotArmyChore.TaskStoreBehaviour
  def completions(tenant_id, since \\ nil) when is_binary(tenant_id) do
    GenServer.call(@server, {:completions, tenant_id, since})
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

  # The store's whole state is read once, at boot — and `BotArmyChore.Repo` is started in the
  # same supervisor while Postgrex connects to its pool in the background, so a read from
  # `init` races the first connection.
  #
  # Measured 2026-11-02: chore booted a few hundred milliseconds ahead of its pool, the rescue
  # below turned that race into `%{}`, and the bot then served an empty house — for as long as
  # it ran, because nothing ever re-read. Both reads a surface makes (`chore.task.list`,
  # `chore.schedule.list`) filter that state, so "the database was not up yet" was answered as
  # "there is nothing to do" — the same lie as a card that draws an unreadable list as an empty
  # one, just committed at boot instead of at read time. Her thirteen chores were in Postgres
  # the whole time.
  #
  # So: wait for the database rather than guessing about it, and if it never arrives, stop and
  # let the supervisor try again. An empty state is only allowed when a read succeeded.
  @load_attempts 15
  @load_retry_ms 2_000

  @impl true
  def init(_opts) do
    Logger.info("TaskStore started")

    case load_tasks(@load_attempts) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        Logger.error("TaskStore could not read its tasks (#{inspect(reason)}); restarting")
        {:stop, {:database_unavailable, reason}}
    end
  end

  @doc false
  # `loader`/`sleep_fun` are injectable so the race itself can be pinned in a test without a
  # database: what must hold is that a failing read is retried and that running out of
  # attempts is an error, never an empty result.
  def load_tasks(
        attempts_left,
        loader \\ &read_all_tasks/0,
        sleep_fun \\ &Process.sleep/1
      )

  def load_tasks(1, loader, _sleep_fun) do
    case loader.() do
      {:ok, tasks} -> {:ok, to_state(tasks)}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_tasks(attempts_left, loader, sleep_fun) do
    case loader.() do
      {:ok, tasks} ->
        {:ok, to_state(tasks)}

      {:error, reason} ->
        Logger.warning(
          "TaskStore could not read its tasks yet (#{inspect(reason)}); retrying in #{@load_retry_ms} ms"
        )

        sleep_fun.(@load_retry_ms)
        load_tasks(attempts_left - 1, loader, sleep_fun)
    end
  end

  defp read_all_tasks do
    {:ok, BotArmyChore.Repo.all(BotArmyChore.Schemas.Task)}
  rescue
    error -> {:error, error}
  end

  defp to_state(tasks) do
    Map.new(tasks, fn task -> {to_string(task.id), schema_to_map(task)} end)
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

      task ->
        task_uuid = Ecto.UUID.cast!(task_id)
        completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        # Captured before the row moves: this is the schedule the press displaces, and the
        # undo has no other way to know it.
        next_due_before =
          case task["next_due_at"] do
            nil ->
              nil

            iso ->
              case DateTime.from_iso8601(iso) do
                {:ok, dt, _} -> dt
                _ -> nil
              end
          end

        # The completion and the row that records *this occasion* are one transaction. The
        # task's own `completed_at` is overwritten on the next completion, so on its own it
        # can say when but never how often — and a habit count built on an overwritten
        # column would be invented. If the history cannot be written, the chore is not
        # completed either: a press that succeeded and left no record would be the same lie
        # the other way round.
        case BotArmyChore.Repo.transaction(fn ->
               db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

               if db_task do
                 changeset =
                   BotArmyChore.Schemas.Task.changeset(
                     db_task,
                     %{"status" => "completed", "completed_at" => completed_at}
                   )

                 updated =
                   case BotArmyChore.Repo.update(changeset) do
                     {:ok, updated} -> updated
                     {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
                   end

                 case BotArmyChore.Repo.insert(
                        BotArmyChore.Schemas.ChoreCompletion.changeset(
                          %BotArmyChore.Schemas.ChoreCompletion{},
                          %{
                            task_id: updated.id,
                            completed_at: DateTime.from_naive!(completed_at, "Etc/UTC"),
                            next_due_at_before: next_due_before,
                            tenant_id: updated.tenant_id,
                            user_id: updated.user_id
                          }
                        )
                      ) do
                   {:ok, _completion} -> updated
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
  def handle_call({:archive, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{"archived_at" => archived} when not is_nil(archived) ->
        # Already in the drawer. Saying so twice is not a second failure.
        {:reply, {:ok, Map.get(state, task_id)}, state}

      _task ->
        write_mark(state, task_id, %{"archived_at" => DateTime.utc_now()})
    end
  end

  @impl true
  def handle_call({:restore, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{"archived_at" => nil} ->
        {:reply, {:ok, Map.get(state, task_id)}, state}

      _task ->
        write_mark(state, task_id, %{"archived_at" => nil})
    end
  end

  @impl true
  def handle_call({:uncomplete, task_id}, _from, state) do
    case Map.get(state, task_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      task ->
        undo_completion(task, task_id, state)
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
        t["tenant_id"] == tenant_id && t["status"] in ["pending", "in_progress"] &&
          is_nil(t["archived_at"])
      end)

    {:reply, {:ok, tasks}, state}
  end

  @impl true
  def handle_call({:list_all, tenant_id}, _from, state) do
    tasks =
      state
      |> Map.values()
      |> Enum.filter(fn t -> t["tenant_id"] == tenant_id && is_nil(t["archived_at"]) end)

    {:reply, {:ok, tasks}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.debug("Clearing all chore tasks")
    {:reply, :ok, %{}}
  end

  @impl true
  def handle_call({:completions, tenant_id, since}, _from, state) do
    import Ecto.Query

    query =
      from(c in BotArmyChore.Schemas.ChoreCompletion,
        where: c.tenant_id == ^tenant_id,
        order_by: [asc: c.completed_at]
      )

    query = if since, do: where(query, [c], c.completed_at >= ^since), else: query

    {:reply, BotArmyChore.Repo.all(query), state}
  rescue
    error ->
      Logger.error("Could not read chore completions: #{inspect(error)}")
      {:reply, {:error, :read_failed}, state}
  end

  @impl true
  def handle_call({:list_overdue_recurring, tenant_id}, _from, state) do
    now = DateTime.utc_now()

    tasks =
      state
      |> Map.values()
      |> Enum.filter(fn t ->
        t["tenant_id"] == tenant_id &&
          is_nil(t["archived_at"]) &&
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
  # Both marks are written the same way: one transaction, one changeset, and the in-memory
  # map is only replaced with what the database actually stored.
  defp write_mark(state, task_id, attrs) do
    task_uuid = Ecto.UUID.cast!(task_id)

    case BotArmyChore.Repo.transaction(fn ->
           case BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid) do
             nil ->
               BotArmyChore.Repo.rollback(:not_found)

             db_task ->
               case BotArmyChore.Schemas.Task.changeset(db_task, attrs)
                    |> BotArmyChore.Repo.update() do
                 {:ok, updated} -> updated
                 {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
               end
           end
         end) do
      {:ok, updated} ->
        task = schema_to_map(updated)
        {:reply, {:ok, task}, Map.put(state, task_id, task)}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, changeset} ->
        Logger.error("Failed to write chore mark: #{inspect(changeset)}")
        {:reply, {:error, :database_error}, state}
    end
  end

  # Undoing a completion is deleting *that occasion* and putting the schedule back where it
  # was, in one transaction. Two things are deliberately not recomputed from the cadence:
  # `next_due_at` comes from the completion row (what it displaced), and `status` comes from
  # the task's own shape — a one-off goes back to pending, a recurring chore goes back to the
  # completed-but-due state it lives in between occasions.
  defp undo_completion(task, task_id, state) do
    import Ecto.Query

    task_uuid = Ecto.UUID.cast!(task_id)

    result =
      BotArmyChore.Repo.transaction(fn ->
        last =
          BotArmyChore.Repo.one(
            from(c in BotArmyChore.Schemas.ChoreCompletion,
              where: c.task_id == ^task_uuid,
              order_by: [desc: c.completed_at, desc: c.inserted_at],
              limit: 1
            )
          )

        if is_nil(last), do: BotArmyChore.Repo.rollback(:no_completion)

        case BotArmyChore.Repo.delete(last) do
          {:ok, _} -> :ok
          {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
        end

        previous =
          BotArmyChore.Repo.one(
            from(c in BotArmyChore.Schemas.ChoreCompletion,
              where: c.task_id == ^task_uuid,
              order_by: [desc: c.completed_at],
              limit: 1
            )
          )

        db_task = BotArmyChore.Repo.get(BotArmyChore.Schemas.Task, task_uuid)

        if is_nil(db_task), do: BotArmyChore.Repo.rollback(:not_found)

        attrs = %{
          "status" => if(task["frequency"] == "once", do: "pending", else: "completed"),
          "completed_at" => previous && DateTime.to_naive(previous.completed_at),
          "next_due_at" => last.next_due_at_before
        }

        case BotArmyChore.Schemas.Task.changeset(db_task, attrs)
             |> BotArmyChore.Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> BotArmyChore.Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, updated} ->
        undone = schema_to_map(updated)
        Logger.info("Undid a chore completion: #{task_id}")
        {:reply, {:ok, undone}, Map.put(state, task_id, undone)}

      {:error, :no_completion} ->
        {:reply, {:error, :no_completion}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, changeset} ->
        Logger.error("Failed to undo chore completion: #{inspect(changeset)}")
        {:reply, {:error, :database_error}, state}
    end
  end

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
        if(task.completed_at,
          do: task.completed_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601(),
          else: nil
        ),
      "next_due_at" =>
        if(task.next_due_at, do: task.next_due_at |> DateTime.to_iso8601(), else: nil),
      "last_completed_at" =>
        if(task.last_completed_at, do: task.last_completed_at |> DateTime.to_iso8601(), else: nil),
      "notification_level" => task.notification_level || 0,
      "last_notified_at" =>
        if(task.last_notified_at, do: task.last_notified_at |> DateTime.to_iso8601(), else: nil),
      "archived_at" =>
        if(task.archived_at, do: task.archived_at |> DateTime.to_iso8601(), else: nil),
      "created_at" => task.inserted_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601(),
      "updated_at" => task.updated_at |> BotArmyLibraryRuntime.Timestamp.utc_iso8601()
    }
  end
end
