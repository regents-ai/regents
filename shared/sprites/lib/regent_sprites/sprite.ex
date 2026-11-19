defmodule RegentSprites.Sprite do
  @moduledoc """
  A machine as Sprites describes it.

  `status` is Sprites' own word for it (`"cold"`, `"warm"` or `"running"`).
  `version` and `environment_version` name the machine image, so a site can record
  exactly what it ran on; Sprites leaves `environment_version` empty on some machines.
  """

  @enforce_keys [:id, :name, :url, :status]
  defstruct [:id, :name, :url, :status, :version, :environment_version]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          url: String.t(),
          status: String.t(),
          version: String.t() | nil,
          environment_version: String.t() | nil
        }

  @doc false
  @spec from_api(term()) :: {:ok, t()} | :error
  def from_api(%{"id" => id, "name" => name, "url" => url, "status" => status} = body)
      when is_binary(id) and is_binary(name) and is_binary(url) and is_binary(status) do
    {:ok,
     %__MODULE__{
       id: id,
       name: name,
       url: url,
       status: status,
       version: body["version"],
       environment_version: body["environment_version"]
     }}
  end

  def from_api(_body), do: :error
end
