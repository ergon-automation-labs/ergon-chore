defmodule BotArmyChore.IntentEvaluatorPromptTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyChore.IntentEvaluator

  # `context.summary.<type>` is an aggregate produced by `AccumulatedContext.compute_summary/1`
  # (`%{count:, values:, latest: %{value:, ...}}`) — never a scalar. These tests carry the real
  # shape: a test that passes `%{}` is green for the right and the wrong read alike.

  describe "build_remind_overdue_defer_prompt/3" do
    test "renders the newest overdue count, not the aggregate map" do
      context = %{
        summary: %{
          overdue_count: %{
            count: 2,
            values: [3, 5],
            latest: %{type: :overdue_count, value: 5, metadata: %{source: "pulse"}}
          }
        }
      }

      prompt =
        IntentEvaluator.build_remind_overdue_defer_prompt(
          "remind_overdue",
          %{score: 0.3, reason: :low_roll},
          context
        )

      assert prompt["text"] =~ "has 5 overdue chore"
      refute prompt["text"] =~ "%{"
      refute prompt["text"] =~ "latest"
    end

    test "an absent observation type reads as 0" do
      prompt =
        IntentEvaluator.build_remind_overdue_defer_prompt(
          "remind_overdue",
          %{score: 0.3, reason: :low_roll},
          %{summary: %{streak_at_risk: %{count: 1, values: [1], latest: %{value: 1}}}}
        )

      assert prompt["text"] =~ "has 0 overdue chore"
    end

    test "accepts a bare summary map as well as a snapshot" do
      prompt =
        IntentEvaluator.build_remind_overdue_defer_prompt(
          "remind_overdue",
          %{score: 0.3, reason: :low_roll},
          %{overdue_count: %{count: 1, values: [7], latest: %{value: 7}}}
        )

      assert prompt["text"] =~ "has 7 overdue chore"
    end
  end
end
