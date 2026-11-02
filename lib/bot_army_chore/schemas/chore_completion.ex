defmodule BotArmyChore.Schemas.ChoreCompletion do
  @moduledoc """
  One occasion of a chore being done.

  Written in the same transaction as the completion itself, so the chore's `completed_at`
  and its history cannot disagree: either the occurrence was recorded or the chore was
  not completed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "chore_completions" do
    field(:task_id, :binary_id)
    field(:completed_at, :utc_datetime_usec)
    field(:tenant_id, :binary_id)
    field(:user_id, :binary_id)

    # What this completion displaced. Undoing the press restores *this* date rather than
    # recomputing one from the cadence, which would move a weekly chore to "tonight + 7"
    # and quietly make the undo a different schedule.
    field(:next_due_at_before, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:task_id, :completed_at, :tenant_id, :user_id, :next_due_at_before])
    |> validate_required([:task_id, :completed_at, :tenant_id])
  end
end
