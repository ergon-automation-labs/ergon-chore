defmodule BotArmyChore.PulsePublisher do
  @moduledoc """
  Publishes health pulses for the Chore bot.

  Tracks chore system metrics:
  - Active chores and assignments
  - Completion rate
  - Overdue items
  """

  use GenServer
  require Logger

  @health_interval_ms 30 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_publish()
    Process.send_after(self(), :publish_health, 2_000)
    {:ok, %{active_chores: 0, completed: 0, overdue: 0}}
  end

  def record_chore_active do
    GenServer.cast(__MODULE__, :active)
  end

  def record_chore_completed do
    GenServer.cast(__MODULE__, :completed)
  end

  def record_chore_overdue do
    GenServer.cast(__MODULE__, :overdue)
  end

  @impl true
  def handle_cast(:active, state) do
    {:noreply, Map.update(state, :active_chores, 1, &(&1 + 1))}
  end

  @impl true
  def handle_cast(:completed, state) do
    {:noreply, Map.update(state, :completed, 1, &(&1 + 1))}
  end

  @impl true
  def handle_cast(:overdue, state) do
    {:noreply, Map.update(state, :overdue, 1, &(&1 + 1))}
  end

  @impl true
  def handle_info(:publish, state) do
    pulse = publish_pulse(state)
    BotArmyChore.IntentEvaluator.record_observations(pulse)
    schedule_publish()
    {:noreply, %{active_chores: 0, completed: 0, overdue: 0}}
  end

  @impl true
  def handle_info(:publish_health, state) do
    publish_system_health(state)
    Process.send_after(self(), :publish_health, @health_interval_ms)
    {:noreply, state}
  end

  defp schedule_publish do
    Process.send_after(self(), :publish, 5 * 60 * 1000)
  end

  defp publish_system_health(metrics) do
    health_signal = if metrics.overdue > 0, do: "degraded", else: "nominal"

    BotArmyRuntime.SynapseHealth.publish(
      source: "bot_army_chore",
      service: "chore",
      health_signal: health_signal
    )
  end

  defp publish_pulse(metrics) do
    health_signal =
      if metrics.overdue > 0, do: "degraded", else: "nominal"

    payload = %{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "service" => "chore",
      "health_signal" => health_signal,
      "metrics" => %{
        "active_chores" => metrics.active_chores,
        "completed" => metrics.completed,
        "overdue" => metrics.overdue
      },
      "observations" => %{
        "overdue_count" => metrics.overdue
      }
    }

    subject = "bot.chore.pulse"

    case BotArmyRuntime.NATS.Publisher.publish(subject, payload) do
      {:ok, _} -> Logger.info("[PulsePublisher] Published chore pulse")
      {:error, reason} -> Logger.warning("[PulsePublisher] Publish failed: #{inspect(reason)}")
    end

    payload
  rescue
    e ->
      Logger.error("[PulsePublisher] Error: #{inspect(e)}")
      %{}
  end
end
