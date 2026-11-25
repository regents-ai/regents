defmodule Regents.Account.Actors.Agent do
  @moduledoc """
  An agent that signed a request with its own key, which the SIWA service
  verified (`RegentsWeb.Account.PairedAgent` builds it). This struct is not
  proof by itself and is never built from client input. An agent is an Agent
  whether or not it is paired.

  `pairing` says whom it acts for, and `with_pairing/1` alone decides it: the
  person's `Regents.Account.Actors.Human` while the shared pairing record names
  this wallet and that person has an account here, `:person_not_here` while the
  person has never signed in here, and `:none` without a pairing. Only while it
  is a `Human` are `pairing_id` and `privy_user_id` (the pairing episode and its
  owner) and `human_account_id` set; otherwise all three are nil. Protected
  work requires the paired shape: a policy admits an agent with
  `{RegentAgents.Checks.Paired, repo: Regents.Repo}`, which also reads the
  pairing again, and a product's write locks it inside its transaction, with
  `{RegentAgents.RequirePairing, repo: Regents.Repo}` on an Ash action or
  `lock_pairing/1` elsewhere. `wallet_addresses` (the person's wallets that are
  addresses, lowercase, which a name claim's owner is matched against) and
  `beneficiary_wallet_address` (the person's main wallet, lowercase, or nil when
  it is not an address; the agent reads its staking position) come with the
  paired shape too.

  `credential_ref` names the signed request's credential, `sha256:` over its
  receipt and key id, so a record can cite it without holding it.
  `registry_url`, `human_id` and `same_person_agent_count` are what the SIWA
  service said about the agent with this request: its page in the agent
  registry, and the World ID person behind it with how many agents that person
  stands behind (`RegentAgents.HumanBacking`), each nil when there is none. The
  person's number is never shown or logged.

  `chain_id` is the chain the agent signed in on, Ethereum (1) or Base (8453),
  `verification_method` how SIWA proved the wallet, and `receipt_expires_at`
  when its receipt runs out. A plain wallet's signature (`:eoa_recovery`) proves
  its key on every chain; a smart wallet's (`:erc1271`, `:erc6492`) only on the
  chain it was checked on, so it counts only on Base. The SIWA answer the site
  reads today (`RegentAgents.HTTP.Hooks`) keeps none of the three, so they are
  nil on every agent this site builds, and `authenticated?/1`, `valid?/1` and
  `refresh/1` refuse it.

  `connection` is set when the agent is a connected app's own identity acting
  with the token its person approved; nothing on this site sets it yet.
  """

  alias RegentAgents.Authority
  alias Regents.Account.Accounts
  alias Regents.Account.Actors.{Human, System}

  @enforce_keys [:wallet_address, :chain_id, :verification_method, :audience]
  @derive {Inspect,
           except: [
             :human_id,
             :connection,
             :privy_user_id,
             :pairing,
             :wallet_addresses,
             :credential_ref
           ]}
  defstruct [
    :wallet_address,
    :chain_id,
    :verification_method,
    :audience,
    :credential_ref,
    :receipt_expires_at,
    :registry_url,
    :human_id,
    :same_person_agent_count,
    :pairing_id,
    :privy_user_id,
    :human_account_id,
    :connection,
    :beneficiary_wallet_address,
    wallet_addresses: [],
    role: :agent,
    pairing: :none
  ]

  @type t :: %__MODULE__{
          wallet_address: String.t(),
          chain_id: 1 | 8453 | nil,
          verification_method: :eoa_recovery | :erc1271 | :erc6492 | :connected_app | nil,
          audience: String.t(),
          credential_ref: String.t() | nil,
          receipt_expires_at: DateTime.t() | nil,
          registry_url: String.t() | nil,
          human_id: String.t() | nil,
          same_person_agent_count: pos_integer() | nil,
          pairing_id: String.t() | nil,
          privy_user_id: String.t() | nil,
          human_account_id: integer() | nil,
          connection: map() | nil,
          beneficiary_wallet_address: String.t() | nil,
          wallet_addresses: [String.t()],
          role: :agent,
          pairing: Human.t() | :none | :person_not_here
        }

  @doc """
  Whether the sign-in itself counts here: a plain wallet on Ethereum or Base, a
  smart wallet or a connected app on Base, for this site's audience.
  """
  @spec authenticated?(term()) :: boolean()
  def authenticated?(%__MODULE__{
        wallet_address: wallet,
        chain_id: chain_id,
        verification_method: method,
        audience: "regents"
      })
      when is_binary(wallet) and
             ((method == :eoa_recovery and chain_id in [1, 8453]) or
                (method in [:erc1271, :erc6492, :connected_app] and chain_id == 8453)),
      do: Regex.match?(~r/\A0x[0-9a-f]{40}\z/, wallet)

  def authenticated?(_), do: false

  @doc """
  The agent with its pairing filled from the shared pairing record and this
  site's account: `{:ok, agent}` with `pairing` a `Human`, `:person_not_here`
  or `:none`, or `{:error, reason}` when either could not be read. The only
  place that decides the pairing. The site's plug
  (`RegentsWeb.Account.PairedAgent`) calls it on a request it verified, and so
  do `refresh/1`, Keyfleet's graph when it rebuilds a queued write's agent
  (`Regents.Keyfleet.Graph.ActorRef`) and its notebook roster
  (`Regents.Keyfleet.Notebooks.Roster`): the pairing check proves the pairing,
  never the signature.
  """
  @spec with_pairing(t()) :: {:ok, t()} | {:error, term()}
  def with_pairing(%__MODULE__{} = agent) do
    case pairing_account(agent.wallet_address) do
      {:ok, pairing, account} -> {:ok, paired(agent, pairing, account)}
      {:error, :not_paired} -> {:ok, unpaired(agent, :none)}
      {:error, :person_not_here} -> {:ok, unpaired(agent, :person_not_here)}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Resolves a verified wallet's live pairing and its local account."
  def pairing_account(wallet) do
    with {:ok, pairing} <- Authority.resolve(Regents.Repo, wallet),
         {:ok, %{} = account} <-
           Accounts.get_by_privy_did(pairing.privy_user_id, actor: %System{}) do
      {:ok, pairing, account}
    else
      {:ok, nil} -> {:error, :person_not_here}
      {:error, reason} -> {:error, reason}
    end
  end

  defp paired(agent, pairing, account) do
    human = Human.for_account(account)

    %{
      agent
      | pairing: human,
        pairing_id: pairing.id,
        privy_user_id: pairing.privy_user_id,
        human_account_id: account.id,
        beneficiary_wallet_address: address(account.wallet_address),
        wallet_addresses: for(wallet <- human.wallet_addresses, address(wallet), do: wallet)
    }
  end

  # A wallet as the agent carries it: lowercase, or nil when it is not an address.
  defp address(wallet) when is_binary(wallet) do
    wallet = String.downcase(wallet)
    if Regex.match?(~r/\A0x[0-9a-f]{40}\z/, wallet), do: wallet
  end

  defp address(_), do: nil

  defp unpaired(agent, pairing) do
    %{
      agent
      | pairing: pairing,
        pairing_id: nil,
        privy_user_id: nil,
        human_account_id: nil,
        beneficiary_wallet_address: nil,
        wallet_addresses: []
    }
  end

  @doc "The same pairing episode with the account's wallets read again, or `{:error, :not_paired}`."
  @spec refresh(term()) :: {:ok, t()} | {:error, :not_paired}
  def refresh(%__MODULE__{pairing: %Human{}, pairing_id: id, privy_user_id: owner} = agent) do
    with true <- authenticated?(agent),
         {:ok, %__MODULE__{pairing: %Human{}, pairing_id: ^id, privy_user_id: ^owner} = current} <-
           with_pairing(agent) do
      {:ok, current}
    else
      _ -> {:error, :not_paired}
    end
  end

  def refresh(_), do: {:error, :not_paired}

  @doc "Whether the agent is signed in and the shared pairing record still names its episode and owner."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{pairing: %Human{}, pairing_id: id, privy_user_id: owner} = agent) do
    authenticated?(agent) and
      match?(
        {:ok, %{id: ^id, privy_user_id: ^owner}},
        Authority.resolve(Regents.Repo, agent.wallet_address)
      )
  end

  def valid?(_), do: false

  @doc """
  Inside the caller's database transaction, reads the paired agent's pairing
  episode again and locks it until the transaction ends, so it cannot be ended
  mid-write. `:ok`, or the refusal `RegentsWeb.Account.PairedAgent` gives:
  `:agent_not_paired`, `:person_not_here` or `:unavailable`. Called for a
  paired agent outside a transaction, it raises.
  """
  @spec lock_pairing(t()) :: :ok | {:error, :agent_not_paired | :person_not_here | :unavailable}
  def lock_pairing(%__MODULE__{pairing: %Human{}} = agent) do
    case Authority.lock(Regents.Repo, agent.pairing_id, agent.privy_user_id, agent.wallet_address) do
      {:ok, _pairing} -> :ok
      {:error, :not_paired} -> {:error, :agent_not_paired}
      {:error, _unreadable} -> {:error, :unavailable}
    end
  end

  def lock_pairing(%__MODULE__{pairing: :person_not_here}), do: {:error, :person_not_here}
  def lock_pairing(%__MODULE__{pairing: :none}), do: {:error, :agent_not_paired}
end
