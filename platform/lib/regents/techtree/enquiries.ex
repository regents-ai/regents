defmodule Regents.Techtree.Enquiries do
  @moduledoc """
  Contact form enquiries left on Techtree's home and service pages.
  """

  use Ash.Domain,
    otp_app: :regents,
    extensions: [AshPhoenix]

  resources do
    resource Regents.Techtree.Enquiries.Enquiry do
      define :send_enquiry, action: :send
      define :list_enquiries, action: :newest
    end
  end
end
