defmodule Regents.Keyfleet.Agents.AvatarBucket do
  @moduledoc """
  The S3-compatible bucket agents' pictures are kept in. Keyfleet writes and
  deletes objects there; pages load each picture straight from the bucket's
  public address (`url/1`), never from Keyfleet.

  Configured under `:regents, :keyfleet_avatar_bucket`: the S3 `endpoint`, `bucket`,
  `region`, `access_key_id` and `secret_access_key`, and the `public_url`
  objects are read from. Every call is made once; whoever asked retries.
  """

  @doc "Stores `bytes` under `key`, to be cached for a year: `:ok` or `{:error, reason}`."
  def put(key, bytes, content_type) do
    request(:put, key,
      body: bytes,
      headers: [
        {"content-type", content_type},
        {"cache-control", "public, max-age=31536000, immutable"}
      ]
    )
  end

  @doc "Deletes the object under `key`, which may already be gone: `:ok` or `{:error, reason}`."
  def delete(key), do: request(:delete, key, [])

  @doc "The public address of the object under `key`."
  def url(key), do: config()[:public_url] <> "/" <> key

  @doc "The origin pictures are served from, for the pages' content security policy."
  def public_origin do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(config()[:public_url])
    %URI{scheme: scheme, host: host, port: port} |> URI.to_string()
  end

  defp request(method, key, options) do
    config = config()

    Req.request(
      [
        method: method,
        base_url: config[:endpoint],
        url: "/#{config[:bucket]}/#{key}",
        aws_sigv4: [
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key],
          region: config[:region],
          service: :s3
        ],
        retry: false,
        redirect: false,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000
      ] ++ options
    )
    |> case do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: 404}} when method == :delete -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:bucket_status, status}}
      {:error, error} -> {:error, error}
    end
  end

  defp config, do: Application.fetch_env!(:regents, :keyfleet_avatar_bucket)
end
