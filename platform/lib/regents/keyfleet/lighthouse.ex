defmodule Regents.Keyfleet.Lighthouse do
  @moduledoc """
  Regent's Lighthouse account, which keeps files on IPFS for good. Keyfleet
  keeps revealed keys' cards there (`Regents.Keyfleet.Keys.DrawPicture`).

  Configured under `:regents, Regents.Keyfleet.Lighthouse`: its upload `url` and the
  account's `api_key`. Each upload is asked once; the picture job retries. The
  same bytes always get the same address, so a repeated upload is harmless.
  """

  # An IPFS address as Lighthouse answers it: version 0 (`Qm`, base58) or
  # version 1 (base32, `b`).
  @cid ~r/\A(Qm[1-9A-HJ-NP-Za-km-z]{44}|b[a-z2-7]{58})\z/

  @doc """
  Keeps `bytes` on IPFS as `filename` of `content_type`: `{:ok, cid}`, the
  address Lighthouse answers, or `{:error, reason}`.
  """
  def add(bytes, filename, content_type) do
    config = Application.fetch_env!(:regents, __MODULE__)

    Req.post(
      base_url: config[:url],
      url: "/api/v0/add",
      auth: {:bearer, config[:api_key]},
      form_multipart: [file: {bytes, filename: filename, content_type: content_type}],
      decode_body: false,
      retry: false,
      redirect: false,
      receive_timeout: 60_000
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        cid(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:lighthouse_status, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp cid(body) do
    case JSON.decode(body) do
      {:ok, %{"Hash" => cid}} when is_binary(cid) ->
        if cid =~ @cid, do: {:ok, cid}, else: {:error, {:lighthouse_answer, body}}

      _other ->
        {:error, {:lighthouse_answer, body}}
    end
  end
end
