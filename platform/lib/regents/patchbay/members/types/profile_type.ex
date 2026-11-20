defmodule Regents.Patchbay.Members.Types.ProfileType do
  use Ash.Type.Enum, values: [:agent, :human, :organization_agent, :official_site_agent]
end
