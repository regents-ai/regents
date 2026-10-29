defmodule RegentsWeb.AgentNamesController do
  @moduledoc """
  A paired agent checks a Regent Name and claims a free one for its person, as
  the Names page does: the same rules, the person's own wallets and free claims,
  and the claim judged again where it is recorded.
  """
  use RegentsWeb, :controller

  alias Regents.Names

  # Far longer than any name a person claims, counted in characters as the
  # contract does; the name's own rules say what is too long.
  @name_limit 255

  def check(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, name} <- name(conn.body_params),
         {:ok, taken} <- taken(name, actor),
         {:ok, claims} <- Names.claims_available(actor: actor) do
      json(conn, %{name: name, problems: Names.label_problems(name), taken: taken, claims: claims})
    else
      :error -> error(conn, "invalid_input")
      {:error, _} -> error(conn, "names_unavailable")
    end
  end

  # A refusal is explained by what is true now: the rules, the name taken, or
  # no free claim left.
  def claim(conn, _params) do
    actor = conn.assigns.actor

    # The name is judged exactly as sent, as the check judges it.
    with {:ok, name} <- name(conn.body_params),
         [] <- Names.label_problems(name) do
      case Names.claim_free_name(name, actor: actor) do
        {:ok, claim} -> conn |> put_status(201) |> json(%{claim: Names.present(claim)})
        {:error, _} -> refused(conn, name, actor)
      end
    else
      :error -> error(conn, "invalid_input")
      problems -> error(conn, "name_breaks_rules", Enum.join(problems, " "))
    end
  end

  defp refused(conn, name, actor) do
    with {:ok, false} <- Names.label_claimed?(name, actor: actor),
         {:ok, %{free: free}} when free > 0 <- Names.claims_available(actor: actor) do
      error(conn, "names_unavailable")
    else
      {:ok, true} -> error(conn, "name_taken")
      {:ok, %{free: 0}} -> error(conn, "no_free_claims")
      {:error, _} -> error(conn, "names_unavailable")
    end
  end

  defp name(%{"name" => name} = params)
       when map_size(params) == 1 and is_binary(name) do
    if String.length(name) in 1..@name_limit, do: {:ok, name}, else: :error
  end

  defp name(_params), do: :error

  # Whether a name is taken is asked only of a name that follows the rules.
  defp taken(name, actor) do
    case Names.label_problems(name) do
      [] -> Names.label_claimed?(name, actor: actor)
      _problems -> {:ok, nil}
    end
  end

  # Every refusal: a code for programs, a message and a hint for people.
  @errors %{
    "invalid_input" =>
      {400, "This request takes only a name in JSON.",
       "Sign a JSON object with one field, name, the Regent Name to check or claim."},
    "name_breaks_rules" =>
      {422, nil, "Change the name so it follows every rule, then send it again."},
    "name_taken" => {409, "That name is already claimed.", "Check another name, then claim it."},
    "no_free_claims" =>
      {409, "Your person has no free claims left.",
       "Tell your person. regents_name_check shows the free claims left."},
    "names_unavailable" =>
      {503, "Names couldn't be read right now.", "Try again in a moment with fresh proof."}
  }

  defp error(conn, code, message \\ nil) do
    {status, default, hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message || default, hint: hint}})
  end
end
