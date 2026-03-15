defmodule BotArmyChore.Formatter do
  @moduledoc """
  Message formatting for Chore Bot non-LLM notifications.

  Formats task notifications, reminders, and structured messages
  with Chore Bot's practical household operations voice.

  Reference: `/docs/north_star_docs/BOT_ARMY_PERSONALITY_NORTH_STAR.md`
  """

  require Logger
  alias BotArmyRuntime.Personality.Formatter

  @doc """
  Format task due notification.

  Used when a task is coming due.
  """
  def format(:task_due, %{"title" => title}) do
    Formatter.with_symbol(:chore_bot, "#{title} is coming due.")
  end

  @doc """
  Format task overdue notification.

  Used when a task is overdue.
  """
  def format(:task_overdue, %{"title" => title, "days_overdue" => days}) do
    Formatter.with_symbol(
      :chore_bot,
      "#{title} is #{days} day#{if days == 1, do: "", else: "s"} overdue."
    )
  end

  @doc """
  Format task completed notification.

  Used when a task is marked complete.
  """
  def format(:task_completed, %{"title" => title}) do
    Formatter.with_symbol(:chore_bot, "Done: #{title}")
  end

  @doc """
  Format task created notification.

  Used when a new task is created.
  """
  def format(:task_created, %{"title" => title}) do
    Formatter.with_symbol(:chore_bot, "New task: #{title}")
  end

  @doc """
  Format escalation notification.

  Used when a recurring task has escalated in urgency.
  """
  def format(:escalation, %{"title" => title, "urgency" => urgency}) do
    prefix = case urgency do
      "urgent" -> "URGENT:"
      "overdue" -> "Overdue:"
      _ -> ""
    end
    Formatter.with_symbol(:chore_bot, "#{prefix} #{title}")
  end

  @doc """
  Format error notification.

  Used when something goes wrong.
  """
  def format(:error, %{"message" => message}) do
    Formatter.with_symbol(:chore_bot, "Something went wrong: #{message}")
  end

  def format(_type, _data) do
    Logger.warning("Unknown Chore formatter type")
    Formatter.with_symbol(:chore_bot, "Something happened.")
  end
end
