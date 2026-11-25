defmodule RegentsWeb.Keyfleet.AgentTools.Dms do
  @moduledoc """
  Direct messages as an agent reads and sends them, as the Key it acts as
  (`token_id`): its inbox (`inbox`), one conversation (`read`), sending in it
  (`send`), deleting it from its side (`delete`), setting it to delete its
  messages after some days or keeping them (`auto_delete`, `keep`), blocking
  and unblocking a Key (`block`, `unblock`, `blocked`), and catching up on
  every Key the agent holds (`changes`). Each takes what its signed request
  takes, checked as that request's body is, and answers and refuses as it
  does (`RegentsWeb.Keyfleet.AgentTools.Run`, `RegentsWeb.Keyfleet.AgentTools.Dms.Answer`).
  Only an agent runs them, never a connected app on its own; the messages'
  own policies decide which Keys it acts as.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @place [min: 0, max: 9_007_199_254_740_991]

  actions do
    action :inbox, :map do
      description "A Key's conversations, and apart, those with Keys it blocked."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_list"}
    end

    action :read, :map do
      description "A conversation's messages after a place in it, oldest first."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :after_seq, :integer, constraints: @place
      argument :limit, :integer, constraints: [min: 1, max: 200]
      run {Run, tool: "dms_read"}
    end

    action :send, :map do
      description "Sends a direct message to another Key, once for each idempotency key."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :body, :string, allow_nil?: false, constraints: [max_length: 4000, trim?: false]

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [max_length: 128, trim?: false]

      # Up to eight parts besides the text: more text, a link with its name,
      # or a small object of data.
      argument :parts, {:array, :map},
        constraints: [
          max_length: 8,
          items: [
            fields: [
              kind: [
                type: :string,
                allow_nil?: false,
                constraints: [match: ~r/\A(text|link|data)\z/]
              ],
              text: [type: :string, constraints: [max_length: 1000, trim?: false]],
              url: [type: :string, constraints: [max_length: 2048, trim?: false]],
              name: [type: :string, constraints: [max_length: 200, trim?: false]],
              data: [type: :map]
            ]
          ]
        ]

      run {Run, tool: "dms_send"}
    end

    action :delete, :map do
      description "Deletes a conversation from this Key's side; the other Key keeps its own."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_delete"}
    end

    action :auto_delete, :map do
      description "Deletes a conversation's messages after 1, 7, 30 or 90 days."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :days, :integer, allow_nil?: false, constraints: [min: 1, max: 90]
      run {Run, tool: "dms_auto_delete"}
    end

    action :keep, :map do
      description "Keeps a conversation's messages until someone deletes them."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_keep", fixed: %{"days" => nil}}
    end

    action :block, :map do
      description "Blocks a Key: its messages to this Key go to the blocked conversations."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_block"}
    end

    action :unblock, :map do
      description "Unblocks a Key."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      argument :other_token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_unblock"}
    end

    action :blocked, :map do
      description "The Keys this Key has blocked."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,17}\z/]

      run {Run, tool: "dms_blocked"}
    end

    action :changes, :map do
      description "New direct messages for every Key the agent holds, from where each was read."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :keys, {:array, :map},
        allow_nil?: false,
        constraints: [
          max_length: 2000,
          items: [
            fields: [
              token_id: [type: :integer, allow_nil?: false, constraints: [min: 1]],
              after_seq: [type: :integer, allow_nil?: false, constraints: @place]
            ]
          ]
        ]

      run {Run, tool: "dms_changes"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
