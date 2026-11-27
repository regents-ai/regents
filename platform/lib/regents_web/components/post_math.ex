defmodule RegentsWeb.Components.PostMath do
  @moduledoc """
  Post-Math visual identity: the Regents Crown-Block Lattice mark and Lattice
  Teal (`--rg-post-math`) capability badge used to denote products and tools
  that ship cryptographic agility, hybrid post-quantum transport, or
  post-math readiness checks.

  Built directly from the 5x3 block lattice of `regents-crown-flat-dark-clear.svg`
  (`viewBox="0 0 252 186"`): the three spires, outer pillars, and five-block base
  remain intact while the center block rotates 45 degrees inside an open lattice
  window to represent swappable cryptographic foundations inside a lasting crown.
  """

  use Phoenix.Component

  @product_status %{
    "Patchbay" => %{
      state: :live,
      short: "Live",
      label: "Post-Math · Live",
      detail: "TLS hybrid PQ & downgrade probes, CBOM diff receipts, authority inventory",
      href: "/patchbay/validate?tab=crypto"
    },
    "Cloak" => %{
      state: :live,
      short: "Live",
      label: "Post-Math · Live",
      detail: "X25519MLKEM768 NEAR TLS transport & ML-DSA-65 release verification",
      href: "/cloak"
    },
    "Autolaunch" => %{
      state: :inventory,
      short: "Inventory",
      label: "Post-Math · Inventory",
      detail: "Safe multisig & Base L1 authority exposure audit in Patchbay",
      href: "/patchbay/validate?tab=crypto#authority-inventory"
    },
    "Keyfleet" => %{
      state: :inventory,
      short: "Inventory",
      label: "Post-Math · Inventory",
      detail: "Fleet treasury & Key-holder authority exposure audit in Patchbay",
      href: "/patchbay/validate?tab=crypto#authority-inventory"
    },
    "SIWA" => %{
      state: :spec,
      short: "Spec",
      label: "Post-Math · Spec",
      detail: "SIWA v3 hybrid ECC + ML-DSA-65 & algorithm expiry contract spec",
      href: "/patchbay/playbooks/ecc-pqc-migration-audit"
    },
    "Techtree" => %{
      state: :planned,
      short: "Planned",
      label: "Post-Math · Planned",
      detail: "Formal Lean 4 & TLS downgrade conformance lane",
      href: "/patchbay/playbooks/techtree-formal-crypto-verification"
    }
  }

  @doc """
  Returns the honest Post-Math capability metadata for a named Regents product,
  or `nil` when a product is an immutable L1 protocol layer without a Post-Math
  software edition.
  """
  @spec for_product(String.t()) :: map() | nil
  def for_product(name) when is_binary(name), do: Map.get(@product_status, name)
  def for_product(_other), do: nil

  attr :size, :integer, default: 16
  attr :class, :string, default: nil
  attr :label, :string, default: nil

  @doc """
  Renders the inline Regents Post-Math Lattice Crown SVG mark.
  """
  def mark(assigns) do
    height = max(10, round(assigns.size * 186 / 252))
    assigns = assign(assigns, :height, height)

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 252 186"
      width={@size}
      height={@height}
      class={["rg-post-math-mark", @class]}
      role={if @label, do: "img", else: nil}
      aria-label={@label}
      aria-hidden={if @label, do: nil, else: "true"}
      focusable="false"
    >
      <g class="rg-post-math-mark__frame">
        <rect x="31" y="46" width="34" height="34" />
        <rect x="103" y="46" width="34" height="34" />
        <rect x="175" y="46" width="34" height="34" />
        <rect x="31" y="82" width="34" height="34" />
        <rect x="175" y="82" width="34" height="34" />
        <rect x="31" y="118" width="34" height="34" />
        <rect x="67" y="118" width="34" height="34" />
        <rect x="103" y="118" width="34" height="34" />
        <rect x="139" y="118" width="34" height="34" />
        <rect x="175" y="118" width="34" height="34" />
      </g>
      <rect
        x="107"
        y="86"
        width="26"
        height="26"
        transform="rotate(45 120 99)"
        class="rg-post-math-mark__core"
      />
    </svg>
    """
  end

  attr :state, :atom, default: :live
  attr :label, :string, default: "Post-Math"
  attr :detail, :string, default: nil
  attr :href, :string, default: nil
  attr :size, :integer, default: 16
  attr :class, :string, default: nil

  @doc """
  Renders a crisp architectural Post-Math badge (optional link) with honest
  capability state (`:live`, `:hybrid`, `:inventory`, `:spec`, or `:planned`).
  """
  def badge(assigns) do
    muted? = assigns.state in [:spec, :planned]
    assigns = assign(assigns, :muted?, muted?)

    ~H"""
    <%= if @href do %>
      <a
        href={@href}
        class={["rg-post-math-badge", @muted? && "rg-post-math-badge--muted", @class]}
        title={@detail}
      >
        <.mark size={@size} />
        <span>{@label}</span>
      </a>
    <% else %>
      <span
        class={["rg-post-math-badge", @muted? && "rg-post-math-badge--muted", @class]}
        title={@detail}
      >
        <.mark size={@size} />
        <span>{@label}</span>
      </span>
    <% end %>
    """
  end

  attr :post_math, :map, required: true

  @doc """
  Renders a fixed corner seal inside a dark ValueCard GPU panel without
  changing the card's text height or wrapping.
  """
  def stamp(assigns) do
    quiet? = assigns.post_math.state in [:spec, :planned]
    assigns = assign(assigns, :quiet?, quiet?)

    ~H"""
    <span
      class={["rg-post-math-stamp", @quiet? && "rg-post-math-stamp--quiet"]}
      title={@post_math.detail}
    >
      <.mark size={14} />
      <span>Post-Math · {@post_math.short}</span>
    </span>
    """
  end
end
