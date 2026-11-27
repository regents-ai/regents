defmodule Regents.Techtree.Factory.Runbook do
  @moduledoc """
  Declarative automation policy carried on a `Regents.Techtree.Factory.Order`
  and forwarded verbatim to `uplift-factory`'s `OrderBridge` (`UpliftFactory.Factory.Runbook`).

  Defaults to `:supervised` with `auto_deliver: false`.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :mode, :atom,
      allow_nil?: false,
      default: :supervised,
      public?: true,
      constraints: [one_of: [:supervised, :auto]]

    attribute :auto_deliver, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :max_gpu_cents, :integer,
      allow_nil?: false,
      default: 500,
      public?: true,
      constraints: [min: 0]

    attribute :default_gpu, :atom,
      allow_nil?: false,
      default: :auto,
      public?: true,
      constraints: [one_of: [:auto, :L4, :G4, :A100, :H100]]

    attribute :default_learning_rate, :float,
      allow_nil?: false,
      default: 0.0002,
      public?: true,
      constraints: [greater_than: 0.0]

    attribute :default_training_mode, :atom,
      allow_nil?: false,
      default: :sft,
      public?: true,
      constraints: [one_of: [:sft, :rl]]
  end

  @doc "Serializes a Runbook struct to the exact string-keyed map expected by `OrderBridge`."
  @spec to_bridge_map(map() | nil) :: map()
  def to_bridge_map(%{mode: mode} = runbook) do
    %{
      "mode" => Atom.to_string(mode),
      "auto_deliver" => runbook.auto_deliver,
      "max_gpu_cents" => runbook.max_gpu_cents,
      "default_gpu" => Atom.to_string(runbook.default_gpu),
      "default_learning_rate" => runbook.default_learning_rate,
      "default_training_mode" => Atom.to_string(runbook.default_training_mode)
    }
  end

  def to_bridge_map(_nil) do
    %{
      "mode" => "supervised",
      "auto_deliver" => false,
      "max_gpu_cents" => 500,
      "default_gpu" => "auto",
      "default_learning_rate" => 0.0002,
      "default_training_mode" => "sft"
    }
  end
end
