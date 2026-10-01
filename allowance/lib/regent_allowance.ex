defmodule RegentAllowance do
  @moduledoc """
  Each person's daily OpenAI allowance, shared by every Regent site.

  A person, named by their Privy user ID, may spend $2.00 a day on OpenAI calls
  made for them, counted across every site together. The day is the UTC day.
  Before a call the site asks `allowed?/1`; after it, the site records what the
  call cost with `record/3`. Nothing is reserved ahead of a call, so the last
  call of a day can finish slightly over the allowance.

  Calls with no person attached are not counted here; each site keeps its own
  limits for those.

  Each site names itself and supplies its repository:

      config :regent_allowance, repo: MySite.Repo, site: "mysite", ash_domains: [RegentAllowance]

  The schema is migrated once, from Regents, with `RegentAllowance.Migrator`.
  """

  use Ash.Domain, otp_app: :regent_allowance

  alias RegentAllowance.OpenAICall
  alias RegentOpenAI.{Error, Reply, Speech, Transcript}

  @daily_usd Decimal.new("2.00")

  resources do
    resource OpenAICall do
      define :record_call, action: :record
    end
  end

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_allowance, :repo)

  @doc "The name this site's calls are recorded under."
  @spec site() :: String.t()
  def site, do: Application.fetch_env!(:regent_allowance, :site)

  @doc "What one person may spend in a UTC day, in US dollars."
  @spec daily_usd() :: Decimal.t()
  def daily_usd, do: @daily_usd

  @doc "Whether the person has spent less than their allowance so far today."
  @spec allowed?(String.t()) :: boolean()
  def allowed?(privy_user_id), do: Decimal.lt?(spent_today(privy_user_id), @daily_usd)

  @doc "What the person's OpenAI calls have cost today, in US dollars, across every site."
  @spec spent_today(String.t()) :: Decimal.t()
  def spent_today(privy_user_id) do
    since = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    OpenAICall
    |> Ash.Query.for_read(:since, %{privy_user_id: privy_user_id, since: since})
    |> Ash.sum!(:cost_usd)
    |> Kernel.||(Decimal.new(0))
  end

  @doc """
  Records what a call made for the person cost: a reply, a transcript, spoken
  audio, or an error OpenAI still billed. `model` is the model the site asked
  for. An error OpenAI did not bill costs nothing, and nothing is recorded.
  """
  @spec record(String.t(), String.t(), Reply.t() | Transcript.t() | Speech.t() | Error.t()) ::
          :ok | {:error, Ash.Error.t()}
  def record(_privy_user_id, _model, %Error{cost_usd: nil}), do: :ok

  def record(privy_user_id, model, %result{usage: usage, cost_usd: %Decimal{} = cost_usd})
      when result in [Reply, Transcript, Speech, Error] do
    %{
      privy_user_id: privy_user_id,
      site: site(),
      model: model,
      input_tokens: usage.input_tokens,
      cached_input_tokens: usage.cached_input_tokens,
      output_tokens: usage.output_tokens,
      cost_usd: cost_usd
    }
    |> record_call()
    |> case do
      {:ok, _call} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
