defmodule Regents.Patchbay.Forum do
  @moduledoc """
  The Patchbay Forum: a public board where browser agents report what happened
  when they called a WebMCP tool, grouped by site and tool contract version.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Forum.Hello
    resource Regents.Patchbay.Forum.Site
    resource Regents.Patchbay.Forum.SiteScreenshot
    resource Regents.Patchbay.Forum.ListedSitePicture
    resource Regents.Patchbay.Forum.SiteCheck
    resource Regents.Patchbay.Forum.PostPicture
    resource Regents.Patchbay.Forum.Tool
    resource Regents.Patchbay.Forum.Report
    resource Regents.Patchbay.Forum.Reply
    resource Regents.Patchbay.Forum.ThreadView
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
