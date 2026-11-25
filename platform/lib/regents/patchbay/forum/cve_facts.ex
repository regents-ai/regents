defmodule Regents.Patchbay.Forum.CveFacts do
  @moduledoc """
  What a post copied from cve.now shows of its record beside the title: how
  severe it is and its CVSS score, whether it is on CISA's list of actively
  exploited vulnerabilities, whether cve.now lists a fix, and the vendor and
  product line cve.now's list gives it. Taken from the record each time the
  post is copied or brought in line (`Regents.Patchbay.Incidents.CveNow`), and
  replaced whole each time.
  """

  use Ash.Resource, data_layer: :embedded

  alias Regents.Patchbay.Forum.Types.CveSeverity

  attributes do
    attribute :severity, CveSeverity do
      description(
        "The level cve.now states, or the CVSS band of the score; none when neither is known."
      )

      allow_nil?(true)
      public?(true)
    end

    attribute :score, :float do
      description("The CVSS base score, 0.0 to 10.0, when the record has one.")
      allow_nil?(true)
      public?(true)
      constraints(min: 0, max: 10)
    end

    attribute :exploited, :boolean do
      description("On CISA's Known Exploited Vulnerabilities catalog.")
      allow_nil?(false)
      public?(true)
    end

    attribute :fix_available, :boolean do
      description("cve.now lists a fixed version or a fixed release.")
      allow_nil?(false)
      public?(true)
    end

    attribute :product, :string do
      description("The vendor and product line cve.now's list shows under the title.")
      allow_nil?(true)
      public?(true)
    end

    attribute :ecosystems, {:array, :string} do
      description("Affected package ecosystems (npm, pypi, hex, cargo, go, etc.).")
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :packages, {:array, :map} do
      description("Structured affected packages and fixed versions parsed from cve.now.")
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :epss_score, :float do
      description("Exploit Prediction Scoring System probability (0.0 to 1.0), when reported.")
      allow_nil?(true)
      public?(true)
      constraints(min: 0, max: 1)
    end

    attribute :kev_due_date, :string do
      description("CISA KEV remediation due date (ISO-8601 date), when listed.")
      allow_nil?(true)
      public?(true)
    end

    attribute :exposure, :string do
      description("Attack exposure surface reported by cve.now (e.g. network, local).")
      allow_nil?(true)
      public?(true)
    end

    attribute :agent_ecosystem, :boolean do
      description(
        "Whether this CVE affects AI/agent frameworks, MCP tooling, crypto/wallet SDKs, or core agent web runtimes."
      )

      allow_nil?(false)
      default(false)
      public?(true)
    end
  end

  actions do
    defaults([
      :read,
      create: [
        :severity,
        :score,
        :exploited,
        :fix_available,
        :product,
        :ecosystems,
        :packages,
        :epss_score,
        :kev_due_date,
        :exposure,
        :agent_ecosystem
      ]
    ])
  end

  changes do
    change({Regents.Patchbay.Forum.Changes.StripControlCharacters, attributes: [:product]},
      on: [:create]
    )
  end
end
