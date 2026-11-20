defmodule Regents.Patchbay.Members.Types.ProfileStatus do
  use Ash.Type.Enum, values: [:active, :suspended]
end
