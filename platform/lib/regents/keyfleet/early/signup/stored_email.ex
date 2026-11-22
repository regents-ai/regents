defmodule Regents.Keyfleet.Early.Signup.StoredEmail do
  @moduledoc """
  Writes an early-access address as it is stored: lowercased, with its host
  in ASCII by the rules this site applies (UTS #46, non-transitional, with
  STD3 rules, which the URL standard browsers follow leaves off), so
  bücher.de is stored as xn--bcher-kva.de and faß.de as xn--fa-hia.de, never
  fass.de. The Unicode and ASCII spellings of one address are then one entry
  on the list. A host with an empty part, or one those rules can't write in
  ASCII, is not an address; among them a few real hosts, such as
  foo_bar.com and ab--cd.com. A host named with a symbol or an emoji is
  refused as typed, by the address's own rule (`Regents.Keyfleet.Early.Signup`), and
  taken in its ASCII spelling: ☃.net is not an address, xn--n3h.net is. The
  attribute's own rule then holds the stored address, as it held the typed
  one.
  """

  use Ash.Resource.Change

  # The characters the rules read as the dot between a host's parts.
  @dots [".", "。", "．", "｡"]

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :email) do
      # An address that failed its check is nil here and stays refused.
      nil ->
        changeset

      # The attribute's rule lets through one @ only.
      email ->
        [local, host] = String.split(email, "@")

        case ascii(host) do
          {:ok, host} ->
            Ash.Changeset.force_change_attribute(
              changeset,
              :email,
              String.downcase(local) <> "@" <> host
            )

          :error ->
            Ash.Changeset.add_error(changeset,
              field: :email,
              message: "has a host that can't be written in ASCII"
            )
        end
    end
  end

  # idna drops an empty first part without a word, which would store another
  # address, so a host with any empty part is refused before it is asked. It
  # answers a host its rules refuse by exiting.
  defp ascii(host) do
    if "" in String.split(host, @dots) do
      :error
    else
      try do
        {:ok, host |> String.to_charlist() |> :idna.encode([:uts46, :std3_rules]) |> to_string()}
      catch
        :exit, _refused -> :error
      end
    end
  end
end
