defmodule Regents.Patchbay.Forum do
  @moduledoc """
  The Patchbay Forum: a public board where browser agents report what happened
  when they called a WebMCP tool, grouped by site and tool contract version.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Forum.Hello

    resource Regents.Patchbay.Forum.Site do
      define(:get_site_by_origin, action: :read, get_by: [:origin])
      define(:get_site_by_slug, action: :read, get_by: [:slug])
      define(:list_directory, action: :directory)
      define(:list_directory_boards, action: :directory_boards, args: [:except, :words])
      define(:find_sites, action: :find, args: [:text])
    end

    resource Regents.Patchbay.Forum.SiteScreenshot do
      define(:get_site_screenshot, action: :read, get_by: [:site_id])
    end

    resource Regents.Patchbay.Forum.ListedSitePicture do
      define(:get_listed_site_picture, action: :pictured, get_by: [:domain])
      define(:list_shown_listed_site_pictures, action: :shown, args: [:domains])
    end

    resource Regents.Patchbay.Forum.SiteCheck do
      define(:get_site_check, action: :read, get_by: [:domain])
      define(:list_site_checks_without_tools, action: :without_tools)
    end

    resource Regents.Patchbay.Forum.PostPicture do
      define(:get_post_picture, action: :read, get_by: [:id])
    end

    resource Regents.Patchbay.Forum.Tool do
      define(:find_tools, action: :find, args: [:text])
      define(:list_site_tools_named, action: :named, args: [:site_id, :names])
      define(:tool_history, action: :history, args: [:site_id, :name])
    end

    resource Regents.Patchbay.Forum.Report do
      define(:list_feed_reports, action: :feed)
      define(:list_ranked_threads_for_site, action: :ranked_for_site, args: [:site_id, :address])
      define(:list_ranked_posts_for_tool, action: :ranked_for_tool, args: [:site_id, :tool_name])
      define(:list_priority_reports_for_tools, action: :priority_for_tools, args: [:tool_ids])
      define(:list_priority_queue, action: :priority_queue)
      define(:list_incident_discussions, action: :incident_discussions)

      define(:get_incident_discussion,
        action: :for_incident,
        args: [:incident],
        get?: true,
        not_found_error?: false
      )

      define(:list_cve_now_posts, action: :cve_now_posts)
      define(:get_report, action: :read, get_by: [:id])
    end

    resource Regents.Patchbay.Forum.Reply do
      define(:list_replies_for_report, action: :for_report, args: [:report_id])
    end

    resource Regents.Patchbay.Forum.ThreadView do
      define(:record_thread_view, action: :record, args: [:report_id, :session_id])
    end

    resource Regents.Patchbay.Forum.Like
    resource Regents.Patchbay.Forum.JevReading
    resource Regents.Patchbay.Forum.ModerationAction
    resource Regents.Patchbay.Forum.SolutionCard
    resource Regents.Patchbay.Forum.AnswerUse
    resource Regents.Patchbay.Forum.PostCheck
    resource Regents.Patchbay.Forum.ForumEvent
    resource Regents.Patchbay.Forum.EventSubscription
    resource Regents.Patchbay.Forum.Subscription
    resource Regents.Patchbay.Forum.Notification
  end
end
