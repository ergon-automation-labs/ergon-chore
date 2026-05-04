defmodule BotArmyChore.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the Chore bot.

  Subscribes to NATS subjects matching Chore message patterns:
  - `chore.task.*` - Chore task events
  - `chore.assignment.*` - Chore assignment events

  Messages are decoded using BotArmyCore.NATS.Decoder and routed to
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

  @reconnect_delay_ms 5000
  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000

  @subjects [
    %{subject: "chore.task.create", type: :subscribe, description: "Create chore task"},
    %{subject: "chore.task.assign", type: :subscribe, description: "Assign chore"},
    %{subject: "chore.task.complete", type: :subscribe, description: "Complete chore"},
    %{subject: "chore.schedule.list", type: :request_reply, description: "List chore schedule"},
    %{subject: "chore.assignment.rotate", type: :subscribe, description: "Rotate assignments"},
    %{subject: "chore.assignment.list", type: :request_reply, description: "List assignments"},
    %{
      subject: "bot_army.chore.intent.remind_overdue",
      type: :subscribe,
      description: "Intent: remind about overdue chores"
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
      opts: opts
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("Connected to NATS, subscribing to chore topics")

        Enum.each(@subjects, fn %{subject: subject} ->
          Gnat.sub(conn, self(), subject)
          Logger.info("Chore consumer subscribed to #{subject}")
        end)

        BotArmyRuntime.Registry.register("chore", @subjects, @version)
        Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.warning(
          "Failed to get NATS connection: #{inspect(reason)}, retrying in #{@reconnect_delay_ms}ms"
        )

        Process.send_after(self(), :retry_subscribe, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("Received NATS message on subject: #{msg.topic}")

      case BotArmyCore.NATS.Decoder.decode(msg.body) do
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
    Logger.warning("Disconnected from NATS, will reconnect")
    Process.send_after(self(), :reconnect, @reconnect_delay_ms)
    {:noreply, %{state | conn: nil, subscriptions: []}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    if length(state.subscriptions) > 0 do
      BotArmyRuntime.Registry.register("chore", @subjects, @version)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  # Private functions

  @doc """
  Route decoded message to appropriate handler based on event type.
  """
  def route_message(message, nats_msg) do
    event = message["event"]

    case event do
      "chore.task.create" -> BotArmyChore.Handlers.TaskHandler.handle_create(message)
      "chore.task.assign" -> BotArmyChore.Handlers.TaskHandler.handle_assign(message)
      "chore.task.complete" -> BotArmyChore.Handlers.TaskHandler.handle_complete(message)
      "chore.schedule.list" -> handle_schedule_list(nats_msg)
      "chore.assignment.rotate" -> BotArmyChore.Handlers.TaskHandler.handle_rotate(message)
      "chore.assignment.list" -> handle_assignment_list(nats_msg)
      _ -> Logger.debug("Unknown Chore event type: #{event}")
    end
  end

  defp handle_schedule_list(nats_msg) do
    if nats_msg.reply_to do
      tasks = BotArmyChore.TaskStore.list_overdue_recurring()

      task_list =
        Enum.map(tasks, fn t ->
          %{
            "id" => t["id"],
            "title" => t["title"],
            "frequency" => t["frequency"],
            "next_due_at" => t["next_due_at"],
            "assigned_to" => t["assigned_to"]
          }
        end)

      response = %{
        "tasks" => task_list
      }

      case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
        {:ok, conn} ->
          Gnat.pub(conn, nats_msg.reply_to, Jason.encode!(response))
          Logger.debug("Published schedule list response")

        {:error, reason} ->
          Logger.warning("Failed to publish schedule list: #{inspect(reason)}")
      end
    end
  end

  defp handle_assignment_list(nats_msg) do
    if nats_msg.reply_to do
      {:ok, tasks} = BotArmyChore.TaskStore.list()
      members = Application.get_env(:bot_army_chore, :household_members, [])

      assignments =
        Enum.reduce(members, %{}, fn member, acc ->
          member_tasks = Enum.filter(tasks, &(&1["assigned_to"] == member))
          Map.put(acc, member, member_tasks)
        end)

      response = %{
        "assignments" => assignments
      }

      case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
        {:ok, conn} ->
          Gnat.pub(conn, nats_msg.reply_to, Jason.encode!(response))
          Logger.debug("Published assignment list response")

        {:error, reason} ->
          Logger.warning("Failed to publish assignment list: #{inspect(reason)}")
      end
    end
  end
end
