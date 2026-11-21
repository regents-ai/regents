defmodule Regents.Keyfleet.Graph.ActorRef do
  @moduledoc """
  Who a graph write is for, as the site names them to the graph machine: which
  account or which agent, by identifiers only. The graph machine rebuilds the
  actor from the database at the write's turn (`actor/2`), so nothing here
  grants a right on the site's word.

  A person is their account's id. The graph reads the account and builds the
  person from it as the site does for every request
  (`Regents.Account.Accounts.SessionAuthority`): an account whose wallet evidence has
  lapsed, or that is gone, acts as nobody, which no Key admits.

  An agent signed in to Keyfleet is its wallet, its pairing (`pairing_id`,
  `privy_user_id`) and the credential that signed the request
  (`credential_ref`, which only names it in the write's audit stamp). The
  graph reads the pairing and the person behind it again
  (`Regents.Account.Actors.Agent.refresh/1`). How the agent signed in (`chain_id`,
  `verification`) is the site's statement, and it can only refuse:
  `Regents.Account.Actors.Agent.authenticated?/1` admits no other pair.
  """

  alias Regents.Account.Accounts
  alias Regents.Account.Accounts.VerifiedSession
  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Account.Actors.System

  @type t ::
          %{required(String.t()) => String.t() | integer() | nil}

  @verifications %{
    "eoa_recovery" => :eoa_recovery,
    "erc1271" => :erc1271,
    "erc6492" => :erc6492,
    "connected_app" => :connected_app
  }

  defguardp text_or_nil(value) when is_binary(value) or is_nil(value)

  @doc "The reference the site sends for `actor`."
  @spec from_actor(Human.t() | Agent.t()) :: t()
  def from_actor(%Human{human_account_id: account_id}),
    do: %{"kind" => "human", "account_id" => account_id}

  def from_actor(%Agent{audience: "regents"} = agent) do
    %{
      "kind" => "agent",
      "wallet" => agent.wallet_address,
      "chain_id" => agent.chain_id,
      "verification" => Atom.to_string(agent.verification_method),
      "credential_ref" => agent.credential_ref,
      "pairing_id" => agent.pairing_id,
      "privy_user_id" => agent.privy_user_id
    }
  end

  @doc "Whether `term` has the shape of a reference; nothing in it is read yet."
  @spec valid?(term()) :: boolean()
  def valid?(%{"kind" => "human", "account_id" => id} = ref)
      when map_size(ref) == 2 and is_integer(id) and id > 0,
      do: true

  def valid?(
        %{
          "kind" => "agent",
          "wallet" => wallet,
          "chain_id" => chain_id,
          "verification" => verification,
          "credential_ref" => credential_ref,
          "pairing_id" => pairing_id,
          "privy_user_id" => privy_user_id
        } = ref
      )
      when map_size(ref) == 7 and is_binary(wallet) and is_integer(chain_id) and
             is_map_key(@verifications, verification) and text_or_nil(credential_ref) and
             text_or_nil(pairing_id) and text_or_nil(privy_user_id),
      do: true

  def valid?(_term), do: false

  @doc """
  The actor `ref` names, read now with `opts` (a read's time limit): `{:ok,
  actor}`, `{:ok, nil}` for a person who acts as nobody, or the error the read
  got.
  """
  @spec actor(t(), keyword()) :: {:ok, Human.t() | Agent.t() | nil} | {:error, term()}
  def actor(%{"kind" => "human", "account_id" => account_id}, opts) do
    with {:ok, accounts} <-
           Accounts.accounts_by_ids([account_id], [actor: %System{}] ++ opts) do
      case accounts do
        [account] -> {:ok, if(VerifiedSession.current?(account), do: Human.for_account(account))}
        [] -> {:ok, nil}
      end
    end
  end

  # Only the identifiers are taken; the pairing and the person behind it are
  # read at the write's turn (`Regents.Keyfleet.Graph.Checks.KeyActor`).
  def actor(%{"kind" => "agent"} = ref, _opts) do
    {:ok,
     %Agent{
       wallet_address: ref["wallet"],
       chain_id: ref["chain_id"],
       verification_method: Map.fetch!(@verifications, ref["verification"]),
       audience: "regents",
       credential_ref: ref["credential_ref"],
       pairing_id: ref["pairing_id"],
       privy_user_id: ref["privy_user_id"]
     }}
  end
end
