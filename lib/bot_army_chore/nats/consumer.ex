defmodule BotArmyChore.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the Chore bot.

  Subscribes to NATS subjects matching Chore message patterns:
  - `chore.task.*` - Chore task events
  - `chore.assignment.*` - Chore assignment events

  Messages are decoded using BotArmyLibraryCore.NATS.Decoder and routed to
  appropriate handlers based on the event type.

  ## Features

  - Automatic subscription to Chore topics
  - Message decoding and validation
  - Event-based routing to handlers
  - Graceful error handling and recovery
  - Comprehensive logging

  ## Connection Management

  The consumer maintains a persistent NATS connection. If the connection
  is lost, it will attempt to reconnect with exponential backoff.
  """

  use GenServer
  require Logger

  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000

  @subjects [
    %{subject: "chore.task.create", type: :request_reply, description: "Create chore task"},
    %{subject: "chore.task.assign", type: :subscribe, description: "Assign chore"},
    %{subject: "chore.task.complete", type: :request_reply, description: "Complete chore"},
    %{subject: "chore.schedule.list", type: :request_reply, description: "List chore schedule"},
    %{
      subject: "chore.task.list",
      type: :request_reply,
      description: "List the open chores, due first"
    },
    %{subject: "chore.assignment.rotate", type: :subscribe, description: "Rotate assignments"},
    %{subject: "chore.assignment.list", type: :request_reply, description: "List assignments"},
    %{
      subject: "bot_army.chore.intent.remind_overdue",
      type: :subscribe,
      description: "Intent: remind about overdue chores"
    },
    %{
      subject: "discord.check_in.response",
      type: :subscribe,
      description: "Discord check-in response (done/defer)"
    }
  ]

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Chore NATS consumer")

    state = %{
      subscriptions: [],
      conn: nil,
      opts: opts,
      reconnect_attempt: 0
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    case GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyLibraryRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("Connected to NATS, subscribing to chore topics")

        Enum.each(@subjects, fn %{subject: subject} ->
          Gnat.sub(conn, self(), subject)
          Logger.info("Chore consumer subscribed to #{subject}")
        end)

        deployment_status =
          Application.get_env(:bot_army_chore, :deployment_status, "experimental")

        case register_with_retry("chore", @subjects, @version, deployment_status, 0) do
          :ok ->
            Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
            {:noreply, %{state | conn: conn}}

          :error ->
            Logger.warning("Could not register with registry, retrying in 1s")
            Process.send_after(self(), :retry_subscribe, 1_000)
            {:noreply, state}
        end

      {:error, reason} ->
        next_attempt = state.reconnect_attempt + 1

        delay =
          BotArmyLibraryRuntime.NATS.Connection.calculate_backoff(state.reconnect_attempt, 1000)

        Logger.warning(
          "Failed to get NATS connection: #{inspect(reason)}, retrying in #{delay}ms (attempt #{next_attempt})"
        )

        Process.send_after(self(), :retry_subscribe, delay)
        {:noreply, %{state | reconnect_attempt: next_attempt}}
    end
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyLibraryRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("Received NATS message on subject: #{msg.topic}")

      case decode_message(msg.body, msg.topic, request_reply_subject?(msg.topic)) do
        {:ok, decoded_message} ->
          route_message(decoded_message, msg)

        {:error, reason} ->
          Logger.warning("Failed to decode message from #{msg.topic}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to NATS")
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    next_attempt = state.reconnect_attempt + 1
    delay = BotArmyLibraryRuntime.NATS.Connection.calculate_backoff(state.reconnect_attempt, 1000)

    Logger.warning(
      "Disconnected from NATS, will reconnect in #{delay}ms (attempt #{next_attempt})"
    )

    Process.send_after(self(), :reconnect, delay)
    {:noreply, %{state | conn: nil, subscriptions: [], reconnect_attempt: next_attempt}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("Reconnected to NATS, re-subscribing")
    {:noreply, %{state | reconnect_attempt: 0}, {:continue, :subscribe}}
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    if state.subscriptions != [] do
      deployment_status =
        Application.get_env(:bot_army_chore, :deployment_status, "experimental")

      register_with_retry("chore", @subjects, @version, deployment_status, 0)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  defp register_with_retry(_bot, _subjects, _version, _status, attempts) when attempts > 3 do
    :error
  end

  defp register_with_retry(bot, subjects, version, status, attempts) do
    BotArmyLibraryRuntime.Registry.register(bot, subjects, version, status)
    :ok
  rescue
    _e ->
      Process.sleep(100 * (attempts + 1))
      register_with_retry(bot, subjects, version, status, attempts + 1)
  end

  # Private functions

  @doc """
  Route decoded message to appropriate handler based on event type.
  """
  def route_message(message, nats_msg) do
    event = message["event"]

    case event do
      "chore.task.create" ->
        BotArmyChore.Handlers.TaskHandler.handle_create(message, nats_msg.reply_to)

      "chore.task.assign" ->
        BotArmyChore.Handlers.TaskHandler.handle_assign(message)

      "chore.task.complete" ->
        BotArmyChore.Handlers.TaskHandler.handle_complete(message, nats_msg.reply_to)

      "chore.schedule.list" ->
        handle_schedule_list(nats_msg)

      "chore.task.list" ->
        handle_task_list(nats_msg)

      "chore.assignment.rotate" ->
        BotArmyChore.Handlers.TaskHandler.handle_rotate(message)

      "chore.assignment.list" ->
        handle_assignment_list(nats_msg)

      "discord.check_in.response" ->
        handle_check_in_response(message)

      _ ->
        Logger.debug("Unknown Chore event type: #{event}")
    end
  end

  defp handle_check_in_response(message) do
    payload = message["payload"] || %{}

    if payload["bot_name"] == "chore" do
      case payload["status"] do
        "done" ->
          complete_payload = %{
            "event_id" => message["event_id"] || Elixir.UUID.uuid4(),
            "tenant_id" => message["tenant_id"] || BotArmyLibraryCore.Tenant.default_tenant_id(),
            "user_id" => payload["user_id"],
            "payload" => %{
              "task_id" => payload["task_id"]
            }
          }

          BotArmyChore.Handlers.TaskHandler.handle_complete(complete_payload)

        "deferred" ->
          defer_count =
            BotArmyLibraryRuntime.DeferTracker.record_defer(
              to_string(payload["user_id"]),
              "chore"
            )

          Logger.info(
            "[Chore] User #{payload["user_id"]} deferred check-in. Count: #{defer_count}"
          )

        _ ->
          :ok
      end
    end
  end

  # A schedule read is the overdue-recurring half: what the reminder loop believes is
  # late. It is deliberately not the list a household works from — "overdue" is a judgement
  # about a chore, and a door that opened on it would be opening on an accusation. The list
  # a card draws is `chore.task.list` below.
  defp handle_schedule_list(nats_msg) do
    reply(nats_msg, fn ->
      tenant_id = BotArmyLibraryCore.Tenant.default_tenant_id()

      %{"tasks" => BotArmyChore.TaskStore.list_overdue_recurring(tenant_id)}
    end)
  end

  # The open chores, due first. This is the one read the household's checklist card is built
  # on, and it answers with an `error` key rather than an empty list when the store could not
  # be read: "there is nothing to do" and "I could not find out" are different answers, and a
  # card that drew the second as the first would be telling her the house is clear when nobody
  # looked.
  #
  # Ordering is a decision, not a preference: `due_date` first (undated last, because a chore
  # with no day is not more urgent than one due today), then oldest first, so the list does not
  # reshuffle itself between two reads of the same chores.
  defp handle_task_list(nats_msg) do
    reply(nats_msg, fn ->
      tenant_id = BotArmyLibraryCore.Tenant.default_tenant_id()

      case task_store().list(tenant_id) do
        {:ok, tasks} ->
          %{"chores" => chore_summaries(tasks)}

        {:error, reason} ->
          %{"chores" => [], "error" => "read_failed", "detail" => inspect(reason)}
      end
    end)
  end

  @doc """
  The wire shape of one chore in a `chore.task.list` answer, ordered as the card draws them.

  Public so the shape can be tested without a broker or a database: what the page parses is
  this function's output, and a shape only exercised through a live store is a shape nobody
  can pin.
  """
  @spec chore_summaries([map()]) :: [map()]
  def chore_summaries(tasks) when is_list(tasks) do
    tasks
    |> Enum.filter(&is_map/1)
    |> Enum.sort_by(fn task ->
      {task["due_date"] == nil, task["due_date"] || "", task["created_at"] || ""}
    end)
    |> Enum.map(fn task ->
      %{
        "id" => task["id"],
        "title" => task["title"],
        "category" => task["category"],
        "frequency" => task["frequency"],
        "status" => task["status"],
        "due_date" => task["due_date"],
        "location" => task["location"],
        "assigned_to" => task["assigned_to"]
      }
    end)
  end

  # Who has which chores. This read used to call `TaskStore.list/0`, an arity the store has
  # never had, so every request crashed the consumer — and because the supervisor restarted it
  # onto the same shared connection, the bot looked healthy while the subject answered nothing.
  defp handle_assignment_list(nats_msg) do
    reply(nats_msg, fn ->
      tenant_id = BotArmyLibraryCore.Tenant.default_tenant_id()
      members = Application.get_env(:bot_army_chore, :household_members, [])

      case task_store().list(tenant_id) do
        {:ok, tasks} ->
          assignments =
            Enum.reduce(members, %{}, fn member, acc ->
              member_tasks = Enum.filter(tasks, &(&1["assigned_to"] == member))
              Map.put(acc, member, member_tasks)
            end)

          %{"assignments" => assignments}

        {:error, reason} ->
          %{"assignments" => %{}, "error" => "read_failed", "detail" => inspect(reason)}
      end
    end)
  end

  # One way to answer a request, so the reads and the two presses cannot drift into
  # different failure modes. Every answer goes out as the fleet's `Reply` envelope
  # (`{"ok": true, "data": …}` / `{"ok": false, "error": …}`) because that is the one shape
  # a surface parses: `fitness.set.list` and `fitness.workout.log` answer the same way, so
  # a card that can draw one of these verbs can draw any of them.
  #
  # A read that raises is answered as a failure, never as an empty list: "there is nothing
  # to do" and "I could not find out" are different answers, and the second drawn as the
  # first is the house telling her it is clear when nobody looked.
  defp reply(%{reply_to: reply_to} = nats_msg, build) when is_binary(reply_to) do
    body =
      try do
        {:ok, build.()}
      rescue
        e ->
          Logger.error("Failed to build #{nats_msg.topic || "request"} answer: #{inspect(e)}")
          {:error, :read_failed}
      end

    encoded =
      case body do
        {:ok, data} ->
          BotArmyLibraryRuntime.NATS.Reply.ok(data)

        {:error, :read_failed} ->
          BotArmyLibraryRuntime.NATS.Reply.error("could not read the chore list", :read_failed)
      end

    publish_raw(reply_to, encoded)
  end

  defp reply(_nats_msg, _build), do: :ok

  @doc """
  Publish an already-encoded answer to a reply address.

  Public so the two presses (`chore.task.create`, `chore.task.complete`) answer through the
  same door as the reads, instead of each growing its own copy of the connection dance.
  """
  def publish_raw(reply_to, encoded) when is_binary(encoded) do
    case GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        Gnat.pub(conn, reply_to, encoded)

      {:error, reason} ->
        Logger.warning("Failed to publish an answer to #{reply_to}: #{inspect(reason)}")
    end
  catch
    kind, reason ->
      # A broker that is not there is a lost answer, not a lost chore: the write already
      # happened, and the caller's card re-reads the list. Raising here would turn a reply
      # into a crash in whichever process asked.
      Logger.warning("Could not answer #{reply_to}: #{inspect({kind, reason})}")
      {:error, :not_connected}
  end

  def publish_raw(_reply_to, _encoded), do: :ok

  # A request/reply verb answers a flat body (what a surface sends) and an envelope (what the
  # fleet sends). Both are accepted; the envelope is tried first so nothing that worked before
  # this change changes meaning.
  defp decode_message(body, _subject, false), do: BotArmyLibraryCore.NATS.Decoder.decode(body)

  defp decode_message(body, subject, true) do
    case BotArmyLibraryCore.NATS.Decoder.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _} ->
        case Jason.decode(body) do
          {:ok, payload} when is_map(payload) -> {:ok, Map.put(payload, "event", subject)}
          _ -> {:error, :decode_error}
        end
    end
  end

  defp request_reply_subject?(subject) do
    Enum.any?(@subjects, fn %{subject: s, type: t} -> s == subject and t == :request_reply end)
  end

  defp task_store, do: Application.get_env(:bot_army_chore, :task_store, BotArmyChore.TaskStore)
end
