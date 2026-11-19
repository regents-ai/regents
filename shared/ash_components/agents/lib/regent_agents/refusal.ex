defmodule RegentAgents.Refusal do
  @moduledoc """
  What an agent is told when its signed request is refused before the site's own
  code runs, the same on every site: the status, and the `code`, `message` and
  `hint` of the answer's `error`.

  A site that runs `Siwa.AgentAuthPlug` for its own agent requests calls
  `describe/2` from its `deny/2` hook for every refusal it did not make itself,
  with the hint that tells an agent how to sign in to that site.
  """

  @type answer :: {400..599, %{code: String.t(), message: String.t(), hint: String.t()}}

  # The shared plug's own refusals keep its reason as the code.
  @plug %{
    duplicate_proof: "A signature header was sent more than once.",
    unsupported_query: "A signed request here takes no query string.",
    missing_signed_body: "Send the body as JSON, signed with the rest of the request."
  }

  @unreachable {503,
                %{
                  code: "siwa_request_failed",
                  message: "The sign-in service could not be reached.",
                  hint: "Try again in a moment."
                }}

  @doc """
  The answer for `refusal`, the map `Siwa.AgentAuthPlug` hands a `deny/2` hook.

  The SIWA service's own refusal is passed on as the service wrote it: its
  status, code, message and hint. A service that could not be reached, or that
  failed without saying why, is `siwa_request_failed` (503). Every other refusal
  is 401 with `sign_in_hint`, the site's line on how an agent signs in: the
  shared plug's own under its reason, the rest as `verification_failed`. That
  includes a service refusal below 500 that came without its own words, whose
  status is not passed on.
  """
  @spec describe(map(), String.t()) :: answer()
  def describe(
        %{siwa_status: status, siwa_code: code, siwa_message: message, siwa_hint: hint},
        _sign_in_hint
      )
      when status in 400..599,
      do: {status, %{code: code, message: message, hint: hint}}

  def describe(%{siwa_status: status}, _sign_in_hint) when status >= 500, do: @unreachable
  def describe(%{reason: :siwa_request_failed}, _sign_in_hint), do: @unreachable

  def describe(%{source: :siwa_plug, reason: reason}, sign_in_hint)
      when is_map_key(@plug, reason),
      do: {401, %{code: Atom.to_string(reason), message: @plug[reason], hint: sign_in_hint}}

  def describe(_refusal, sign_in_hint) do
    {401,
     %{
       code: "verification_failed",
       message: "The signed agent request could not be verified.",
       hint: sign_in_hint
     }}
  end
end
