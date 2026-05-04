defmodule BotArmyChore.VetoRules do
  @moduledoc false

  alias BotArmyRuntime.Intent.AccumulatedContext

  @doc """
  Veto GTD nudge intents when there are overdue chores.
  If the user has overdue chores, a nudge about stale GTD tasks
  is counterproductive — they should focus on clearing chores first.
  """
  @spec veto_nudge_when_overdue_chores(map()) :: boolean()
  def veto_nudge_when_overdue_chores(_envelope) do
    case AccumulatedContext.latest("chore", :overdue_count) do
      nil -> false
      entry -> entry.value > 0
    end
  end
end
