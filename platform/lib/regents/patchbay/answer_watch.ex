defmodule Regents.Patchbay.AnswerWatch do
  @moduledoc """
  The weekly answer check: what ChatGPT and Perplexity answer when asked the
  questions Patchbay should be the answer to, and whether they name or link
  Patchbay. Every answer is written down with the addresses it cites
  (`Answer`).
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.AnswerWatch.Answer
  end
end
