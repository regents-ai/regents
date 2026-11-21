defmodule Regents.Keyfleet.Code.Pass do
  @moduledoc """
  The pass every request to the code store carries, as `Authorization:
  Bearer`: an ES256 JWT signed with the notebook hubs' keys
  (`Regents.Keyfleet.Notebooks.Pass.sign/2`), for the audience `keyfleet-code`.

  `fleet` names the one repository it opens, a project's (`Regents.Keyfleet.Projects.Project`,
  `repository`), and `scope` what it allows:
  `push` (copy and send changes, for the key holder whose wallet is `sub`, as
  `did:pkh:eip155:8453:<wallet>`, the key's chain), `read` (copy), `create` (make the
  repository) or `delete` (delete it for good), the last three with `sub`
  `keyfleet`. It lasts
  `pass_ttl_seconds`.
  """

  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Notebooks.Pass

  @audience "keyfleet-code"

  @doc "A pass to send changes to the repository as the holder of `wallet`."
  def push(repository, wallet), do: mint(repository, "push", "did:pkh:eip155:8453:" <> wallet)

  @doc "A pass to copy the repository, for a key whose edits are restricted."
  def read(repository), do: mint(repository, "read", "keyfleet")

  @doc "A pass to make the repository."
  def create(repository), do: mint(repository, "create", "keyfleet")

  @doc "A pass to delete the repository, when its project is deleted."
  def delete(repository), do: mint(repository, "delete", "keyfleet")

  defp mint(repository, scope, subject) do
    Pass.sign(
      %{"aud" => @audience, "fleet" => repository, "scope" => scope, "sub" => subject},
      Code.config()[:pass_ttl_seconds]
    )
  end
end
