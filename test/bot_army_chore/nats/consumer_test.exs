defmodule BotArmyChore.NATS.ConsumerTest do
  use ExUnit.Case
  @moduletag :nats

  alias BotArmyChore.NATS.Consumer

  @keys ~w(id title category frequency status due_date location assigned_to)

  describe "chore_summaries/1 — the shape a checklist card parses" do
    test "sends exactly the keys the card draws, and nothing else" do
      [summary] =
        Consumer.chore_summaries([
          %{
            "id" => "t-1",
            "tenant_id" => "house",
            "title" => "Laundry service",
            "category" => "chore",
            "frequency" => "weekly",
            "status" => "pending",
            "due_date" => "2026-10-25",
            "location" => "bathroom",
            "assigned_to" => nil,
            "notification_level" => 2,
            "created_at" => "2026-10-20T10:00:00Z"
          }
        ])

      assert Map.keys(summary) |> Enum.sort() == Enum.sort(@keys)
    end

    test "due first, undated last, oldest first within a day" do
      chores =
        Consumer.chore_summaries([
          %{
            "id" => "undated",
            "title" => "Undated",
            "due_date" => nil,
            "created_at" => "2026-10-01"
          },
          %{
            "id" => "later",
            "title" => "Later",
            "due_date" => "2026-11-02",
            "created_at" => "2026-10-02"
          },
          %{
            "id" => "second",
            "title" => "Second",
            "due_date" => "2026-10-26",
            "created_at" => "2026-10-03"
          },
          %{
            "id" => "first-b",
            "title" => "First B",
            "due_date" => "2026-10-26",
            "created_at" => "2026-10-05"
          },
          %{
            "id" => "first-a",
            "title" => "First A",
            "due_date" => "2026-10-26",
            "created_at" => "2026-10-04"
          }
        ])

      assert Enum.map(chores, & &1["id"]) == ~w(second first-a first-b later undated)
    end

    test "a chore without a due date does not outrank one due today" do
      chores =
        Consumer.chore_summaries([
          %{
            "id" => "undated",
            "title" => "Undated",
            "due_date" => nil,
            "created_at" => "2026-01-01"
          },
          %{
            "id" => "today",
            "title" => "Today",
            "due_date" => "2026-10-25",
            "created_at" => "2026-10-25"
          }
        ])

      assert Enum.map(chores, & &1["id"]) == ~w(today undated)
    end

    test "anything that is not a task map is dropped rather than drawn" do
      assert Consumer.chore_summaries([%{"id" => "ok", "title" => "Fine"}, :junk, nil])
             |> length() == 1

      assert Consumer.chore_summaries([]) == []
    end
  end
end
