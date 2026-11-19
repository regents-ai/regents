defmodule RegentIdentity.ProfileName do
  @moduledoc """
  An Ash calculation for a site's account resource: the name the person set in
  their shared Regent profile, the same on every Regent site signing in with
  the site's Privy app; nil until they set one.

  The account resource has a `privy_user_id` attribute, and the site names its
  app by `otp_app`, whose `:privy` settings hold the `app_id`:

      calculate :display_name, :string, {RegentIdentity.ProfileName, otp_app: :my_app}
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:privy_user_id]

  @impl true
  def calculate(accounts, opts, _context) do
    app_id =
      opts
      |> Keyword.fetch!(:otp_app)
      |> Application.fetch_env!(:privy)
      |> Keyword.fetch!(:app_id)

    people = Enum.map(accounts, & &1.privy_user_id)

    # Names are public, so they are read whoever asks; only the name leaves.
    RegentIdentity.Profile
    |> Ash.Query.for_read(:names, %{app_id: app_id, privy_user_ids: people})
    |> Ash.Query.select([:privy_user_id, :display_name])
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, profiles} ->
        names = Map.new(profiles, &{&1.privy_user_id, &1.display_name})
        {:ok, Enum.map(accounts, &names[&1.privy_user_id])}

      {:error, error} ->
        {:error, error}
    end
  end
end
