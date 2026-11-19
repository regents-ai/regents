defmodule RegentSprites.Checkpoint do
  @moduledoc """
  A saved copy of a machine's disk that it can be restored to.

  `id` is Sprites' own short name, such as `"v3"`; the list also holds `"Current"`,
  the live disk. Every restore first saves the disk as a checkpoint of its own,
  commented `"pre-restore …"`, so ids are not predictable: find a checkpoint by the
  comment it was made with.
  """

  @enforce_keys [:id, :created_at, :auto?]
  defstruct [:id, :comment, :created_at, :auto?]

  @type t :: %__MODULE__{
          id: String.t(),
          comment: String.t() | nil,
          created_at: DateTime.t(),
          auto?: boolean()
        }

  @doc false
  @spec from_api(term()) :: {:ok, t()} | :error
  def from_api(%{"id" => id, "create_time" => create_time, "is_auto" => auto?} = body)
      when is_binary(id) and is_binary(create_time) and is_boolean(auto?) do
    with {:ok, created_at, _offset} <- DateTime.from_iso8601(create_time) do
      {:ok, %__MODULE__{id: id, comment: body["comment"], created_at: created_at, auto?: auto?}}
    else
      {:error, _reason} -> :error
    end
  end

  def from_api(_body), do: :error
end
