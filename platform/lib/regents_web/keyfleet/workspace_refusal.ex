defmodule RegentsWeb.Keyfleet.WorkspaceRefusal do
  @moduledoc """
  How a refused workspace request is answered, the same over a signed agent
  request (`RegentsWeb.Keyfleet.AgentGraphController`), at the Claude connector's
  address (`RegentsWeb.Keyfleet.ToolErrors`) and in a preview of the write
  (`RegentsWeb.Keyfleet.Preview`): its status, and a body with the
  workspace's own reason and what to do next. Every refusal here carries
  `details`, empty unless it says more, but a coming-soon fleet's and a
  closed project's, which answer as every agent request about one does.
  """

  alias Regents.Keyfleet.Graph.Errors.{
    ComingSoonFleetError,
    EditsRestrictedError,
    IndeterminateError,
    MembersOnlyError,
    NotKeyHolderError,
    RefusedError,
    UnavailableError,
    UnknownFleetError,
    WriteLimitError
  }

  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects.Errors.UnknownProjectError
  alias RegentsWeb.Keyfleet.Refusal

  # The workspace's own refusals: the status each is answered with, and what
  # to do next. The workspace's reason is the message.
  @workspace_refusals %{
    "bad_request" =>
      {400, "The body doesn't fit this operation. Check it against the docs, then send it again."},
    "not_found" =>
      {404,
       "Check the id: an item's id is its type, `#` and its number, such as `task#27`. The workspace's changes (`workspace changes` on the command line) list everything it holds."},
    "conflict" =>
      {409,
       "details.object is the item as it is now. Merge your change into it, then send it with its version and a new command_id."},
    "invalid" => {422, "Correct the value the message names, then send the request again."},
    "forbidden_field" =>
      {422,
       "Leave out the fields details.fields names. details.allowed, when present, lists the fields this kind of item takes; a task is marked done by submitting it."},
    "not_owner" =>
      {403,
       "Join a task to work on it. Only the Key that created an item changes the rest, and only it changes a task's title, deliverable or acceptance criteria; link your own item to it, or fork a task to make your own copy. details.owner_key names that Key."},
    "self_review" =>
      {403,
       "Ask a member whose Key never joined, changed or submitted the task, from another wallet, to review it."},
    "duplicate_mismatch" =>
      {422, "This command_id was used for a different change. Use a new command_id."},
    "over_budget" =>
      {422,
       "details.bytes is the size of the change at details.seq. Send max_bytes of at least that, or leave it out."},
    "packet_too_large" =>
      {422,
       "details.bytes is the packet's size and details.max_bytes the most allowed. Name fewer items, or send max_bytes of at least details.bytes, up to 262144."}
  }

  @doc "The status and body refusing a workspace request for `error`, or nil for an error of no workspace refusal."
  @spec for_error(term()) :: {pos_integer(), map()} | nil
  def for_error(%RefusedError{code: code, reason: reason, details: details})
      when code in ~w(project_archived project_unknown),
      do: {project_status(code), Refusal.closed(code, reason, details)}

  def for_error(%RefusedError{code: code, reason: reason, details: details}) do
    {status, hint} = Map.fetch!(@workspace_refusals, code)
    {status, %{error: %{code: code, message: reason, hint: hint, details: details}}}
  end

  def for_error(%UnknownFleetError{}), do: refusal(404, "fleet_unknown")
  def for_error(%ComingSoonFleetError{}), do: {404, Refusal.body("fleet_coming_soon")}
  def for_error(%UnknownProjectError{}), do: refusal(404, "project_unknown")
  def for_error(%OwnershipRefreshingError{}), do: refusal(503, "ownership_refreshing")
  def for_error(%NotKeyHolderError{}), do: refusal(403, "not_a_key_holder")
  def for_error(%EditsRestrictedError{}), do: refusal(403, "edits_restricted")
  def for_error(%UnavailableError{}), do: refusal(503, "graph_unavailable")
  def for_error(%WriteLimitError{}), do: refusal(429, "workspace_limit_reached")
  def for_error(%MembersOnlyError{}), do: refusal(403, "workspace_members_only")

  def for_error(%IndeterminateError{}),
    do: refusal(503, "indeterminate", %{retry_same_command_id: true})

  def for_error(_error), do: nil

  @doc """
  The status and body refusing a workspace action whose run answered `error`,
  as its signed request answers it: the first error it holds with a workspace
  refusal (`for_error/1`), else its policy's refusal, before the write took
  its turn, or an input it doesn't take.
  """
  @spec for_action_error(Exception.t()) :: {pos_integer(), map()}
  def for_action_error(%{errors: errors} = error),
    do: Enum.find_value(errors, &for_error/1) || unexplained(error)

  defp unexplained(%Ash.Error.Forbidden{}), do: refusal(403, "not_a_key_holder")
  defp unexplained(%Ash.Error.Invalid{}), do: refusal(422, "invalid_request")

  @doc "The status and the site's body refusing with `code`, with `details`."
  @spec refusal(pos_integer(), String.t(), map()) :: {pos_integer(), map()}
  def refusal(status, code, details \\ %{}),
    do: {status, put_in(Refusal.body(code), [:error, :details], details)}

  defp project_status("project_archived"), do: 409
  defp project_status("project_unknown"), do: 404
end
