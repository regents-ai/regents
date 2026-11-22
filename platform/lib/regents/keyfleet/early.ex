defmodule Regents.Keyfleet.Early do
  @moduledoc """
  The early-access list: the email addresses people leave on `/early` while
  Keyfleet is closed, kept only to tell them when it opens.
  """
  use Ash.Domain

  resources do
    resource Regents.Keyfleet.Early.Signup
  end
end
