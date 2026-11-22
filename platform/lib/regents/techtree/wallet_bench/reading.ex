defmodule Regents.Techtree.WalletBench.Reading do
  @moduledoc """
  The Wallet Bench as last read: every attempt with its turns and model spend,
  newest first, every extra note by version, and `read_at`, when the database
  was read (to the second). The page (`/techtree/wallet-bench`), its Markdown
  and the scores feed all build from this one reading, so they always agree.

  A reading is kept on this machine for 30 seconds and shared by every caller,
  so the page's first answer and its live connection, the Markdown and the
  feed read the database at most once in that time. A failed read raises and
  is not kept: the next caller reads again.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  alias Regents.Techtree.WalletBench
  alias Regents.Techtree.WalletBench.{Attempt, VersionNote}

  @kept :timer.seconds(30)

  @type t :: %{attempts: [Attempt.t()], notes: [VersionNote.t()], read_at: DateTime.t()}

  @doc "The bench as last read, read again when the kept reading is more than 30 seconds old."
  @spec reading() :: t()
  def reading do
    case get!(:reading) do
      nil -> read_and_keep()
      reading -> reading
    end
  end

  defp read_and_keep do
    reading = read()
    put!(:reading, reading, ttl: @kept)
    reading
  end

  defp read do
    attempts = WalletBench.list_attempts!(load: [:turns, :model_spend_usd])
    notes = WalletBench.list_version_notes!()
    %{attempts: attempts, notes: notes, read_at: DateTime.utc_now() |> DateTime.truncate(:second)}
  end
end
