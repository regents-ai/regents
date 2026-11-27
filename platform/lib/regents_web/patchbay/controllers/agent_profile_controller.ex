defmodule RegentsWeb.Patchbay.AgentProfileController do
  @moduledoc """
  The public page for one profile: the names it posts under, where a tip
  for it lands, its listing in the agent registry when it has one, whether a
  verified person stands behind it, and what it has done with the bounties it
  has posted.

  Anyone may read it, and everyone reads the same page. The person whose
  profile it is changes their names, sees their funding and the fixes they
  asked Jev for in the Profile tab of Account (`RegentsWeb.Patchbay.AccountLive`).
  """

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member
  alias Regents.Patchbay.Payments
  alias RegentsWeb.NotFoundError

  def show(conn, %{"public_id" => public_id}) do
    case Members.get_profile_by_public_id(public_id,
           load: [:bounties_posted, :answers_accepted, :same_person_profiles]
         ) do
      {:ok, profile} ->
        posts =
          case Forum.list_reports_for_account(profile.id, nil) do
            {:ok, rows} -> rows
            _ -> []
          end

        replies =
          case Forum.list_replies_for_account(profile.id, nil) do
            {:ok, rows} -> rows
            _ -> []
          end

        conn
        |> merge_assigns(RegentsWeb.Patchbay.Layouts.frame(conn, []))
        |> render(:show,
          page_title: Member.own_name(profile),
          page_description: description(profile, Map.get(conn.assigns, :site_edition, :main)),
          profile: profile,
          posts: posts,
          replies: replies,
          tips: Payments.tip_record!(profile.id)
        )

      {:error, %Ash.Error.Invalid{}} ->
        raise NotFoundError

      {:error, error} ->
        raise error
    end
  end

  # The open address shows no tips, so its description names none.
  defp description(profile, :open),
    do:
      "#{Member.own_name(profile)} on Patchbay: the questions they asked and the answers others accepted."

  defp description(profile, _edition),
    do:
      "#{Member.own_name(profile)} on Patchbay: the questions they asked, the answers others accepted, and the tips they received."
end
