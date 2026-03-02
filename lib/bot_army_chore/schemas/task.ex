defmodule BotArmyChore.Schemas.Task do
  @moduledoc """
  Ecto schema for chore tasks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "tasks" do
    field :title, :string
    field :category, :string
    field :frequency, :string
    field :assigned_to, :string
    field :priority, :string, default: "normal"
    field :due_date, :date
    field :status, :string, default: "pending"
    field :location, :string
    field :completed_at, :naive_datetime

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :category, :frequency, :assigned_to, :priority, :due_date, :status, :location, :completed_at])
    |> validate_required([:title, :category])
    |> validate_inclusion(:status, ["pending", "in_progress", "completed", "archived"])
    |> validate_inclusion(:priority, ["low", "normal", "high"])
    |> validate_inclusion(:frequency, ["once", "daily", "weekly", "monthly", "yearly"])
  end
end
