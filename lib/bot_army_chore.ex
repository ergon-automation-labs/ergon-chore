defmodule BotArmyChore do
  @moduledoc """
  BotArmyChore is the chore and household task bot implementation.

  Handles chore scheduling, assignment tracking, and completion management
  within the Bot Army ecosystem.

  ## Schemas

  Message schemas are defined in `bot_army_schemas_chore` and deployed to:
  `/etc/bot_army/schemas/chore/`

  The bot consumes messages from NATS subjects like:
  - `chore.schedule.create` - Create chore schedule
  - `chore.assignment.assign` - Assign chore to person
  - `chore.completion.mark` - Mark chore as complete
  """

  @version "0.1.0"

  def version do
    @version
  end
end
