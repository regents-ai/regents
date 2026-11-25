defmodule RegentHttp.Public do
  @moduledoc """
  Requests to an address someone else supplied, such as an app's published
  identity or an MCP Events callback, without letting that address reach the
  site's own network. Every Regent package that calls such an address uses
  this module.

  The host is resolved first and every answer must be a public address; Mint
  then connects to that checked address while the original host stays the HTTP
  Host, TLS SNI and certificate name, so a second DNS answer cannot redirect
  the connection. HTTPS only, one connection per call, no proxies, redirects,
  pools or retries, a total deadline and a byte limit on the answer.

  `config :regent_http, :public_client, Stub` replaces the network, where
  `Stub.request/3` takes the same arguments.
  """

  @timeout_ms 5_000
  @ipv4_denied [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @type response :: %{
          status: pos_integer(),
          headers: [{String.t(), String.t()}],
          body: binary() | nil
        }

  @doc """
  Sends `method` (`:get`, `:head`, or `:post`) to `url`.

  - `:max_bytes` (required) bounds the answer's headers and body; a longer body
    is `{:error, :too_large}`.
  - `:timeout` is the whole call's deadline in milliseconds (default 5000).
  - `:headers` are sent as given, and `:body` with a POST.
  - `answer: :headers` returns as soon as a 2xx status's headers arrive, with
    `body: nil`, for a receiver that acknowledges on receipt.

  A status of 300 or more is returned at once with an empty body. Supply
  `:body_statuses` to read the bounded body for specific 4xx or 5xx statuses.
  Redirects are never followed.
  """
  @spec request(:get | :head | :post, String.t(), keyword()) ::
          {:ok, response()} | {:error, atom()}
  def request(method, url, opts) when method in [:get, :head, :post] do
    Keyword.fetch!(opts, :max_bytes)

    case Application.get_env(:regent_http, :public_client) do
      nil -> send_request(method, url, opts)
      stub -> stub.request(method, url, opts)
    end
  end

  @doc "`request(:get, url, opts)`."
  def get(url, opts), do: request(:get, url, opts)

  @doc """
  Checks an address this module may call: HTTPS, a port, no user or fragment,
  no control characters, and a host name or a public literal address.
  """
  @spec uri(term()) :: {:ok, URI.t()} | {:error, :invalid_url}
  def uri(url) when is_binary(url) and byte_size(url) in 1..8192 do
    with {:ok, uri} <- URI.new(url),
         true <- uri.scheme == "https" and is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <- is_integer(uri.port) and uri.port in 1..65_535,
         true <- valid_host?(uri.host),
         true <- not Regex.match?(~r/[\x00-\x20\x7f\\]/, url) do
      {:ok, uri}
    else
      _ -> {:error, :invalid_url}
    end
  end

  def uri(_), do: {:error, :invalid_url}

  @doc "Whether `uri/1` accepts `url`."
  @spec valid_url?(term()) :: boolean()
  def valid_url?(url), do: match?({:ok, _}, uri(url))

  @doc "Whether an IP tuple is globally routable; transition and mapped IPv6 are refused."
  def public_ip?({a, b, c, d} = ip)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
    ip != {168, 63, 129, 16} and
      not Enum.any?(@ipv4_denied, fn {network, bits} -> in_network?(ip, network, bits) end)
  end

  def public_ip?({a, b, c, d, e, f, g, h})
      when a in 0..65_535 and b in 0..65_535 and c in 0..65_535 and d in 0..65_535 and
             e in 0..65_535 and f in 0..65_535 and g in 0..65_535 and h in 0..65_535 do
    # Only global unicast. Exclude IANA protocol space, documentation and 6to4.
    a in 0x2000..0x3FFF and not (a == 0x2001 and b < 0x0200) and
      not (a == 0x2001 and b == 0x0DB8) and a != 0x2002 and
      not (a == 0x3FFF and b < 0x1000)
  end

  def public_ip?(_), do: false

  defp send_request(method, url, opts) do
    started_at = System.monotonic_time()
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, @timeout_ms)
    max_bytes = Keyword.fetch!(opts, :max_bytes)

    result =
      with {:ok, uri} <- uri(url),
           {:ok, address} <- resolve(uri.host, deadline),
           {:ok, conn} <- connect(uri, address, max_bytes, deadline) do
        try do
          send_on(conn, method, uri, opts, max_bytes, deadline)
        after
          Mint.HTTP.close(conn)
        end
      end

    # The host is someone else's choice, so it is not a measurement label.
    :telemetry.execute(
      [:regent_http, :public_request],
      %{duration: System.monotonic_time() - started_at},
      %{method: method, result: result_status(result)}
    )

    result
  end

  defp valid_host?(host) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} ->
        public_ip?(address)

      {:error, _} ->
        byte_size(host) <= 253 and
          Regex.match?(~r/\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z/, host) and
          Enum.all?(String.split(host, "."), fn label ->
            byte_size(label) in 1..63 and not String.starts_with?(label, "-") and
              not String.ends_with?(label, "-")
          end)
    end
  end

  defp resolve(host, deadline) do
    host = String.to_charlist(host)

    case :inet.parse_strict_address(host) do
      {:ok, ip} -> if public_ip?(ip), do: {:ok, ip}, else: {:error, :non_public_address}
      {:error, _} -> resolve_name(host, deadline)
    end
  end

  defp resolve_name(host, deadline) do
    # Check every answer, not merely whichever address is used.
    answers =
      for family <- [:inet, :inet6] do
        :inet.getaddrs(host, family, remaining(deadline))
      end

    addresses = for {:ok, ips} <- answers, ip <- ips, do: ip

    cond do
      System.monotonic_time(:millisecond) >= deadline -> {:error, :timeout}
      Enum.any?(answers, &(&1 == {:error, :timeout})) -> {:error, :timeout}
      addresses == [] -> {:error, :dns_error}
      not Enum.all?(addresses, &public_ip?/1) -> {:error, :non_public_address}
      true -> {:ok, hd(addresses)}
    end
  end

  defp connect(uri, address, max_bytes, deadline) do
    ipv6? = tuple_size(address) == 8

    case Mint.HTTP.connect(:https, address, uri.port,
           hostname: uri.host,
           protocols: [:http1],
           mode: :passive,
           max_header_list_size: max(max_bytes, 8_192),
           transport_opts: [
             timeout: remaining(deadline),
             send_timeout: remaining(deadline),
             send_timeout_close: true,
             inet4: not ipv6?,
             inet6: ipv6?,
             cacerts: :public_key.cacerts_get()
           ]
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, error} -> {:error, network_reason(error)}
    end
  end

  defp send_on(conn, method, uri, opts, max_bytes, deadline) do
    headers = Keyword.get(opts, :headers, [])
    body = if method == :post, do: Keyword.fetch!(opts, :body)
    answer = Keyword.get(opts, :answer, :body)
    path = if uri.path in [nil, ""], do: "/", else: uri.path
    path = if is_nil(uri.query), do: path, else: path <> "?" <> uri.query
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    host = if uri.port == 443, do: host, else: host <> ":" <> Integer.to_string(uri.port)

    headers = [
      {"host", host} | Enum.reject(headers, fn {key, _} -> String.downcase(key) == "host" end)
    ]

    verb = method |> Atom.to_string() |> String.upcase()

    case Mint.HTTP.request(conn, verb, path, headers, body) do
      {:ok, conn, ref} ->
        response = %{
          status: nil,
          headers: nil,
          body: "",
          answer: answer,
          body_statuses: Keyword.get(opts, :body_statuses, [])
        }

        receive_response(conn, ref, max_bytes, deadline, response)

      {:error, _conn, error} ->
        {:error, network_reason(error)}
    end
  end

  defp receive_response(conn, ref, max_bytes, deadline, response) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case Mint.HTTP.recv(conn, 0, remaining(deadline)) do
        {:ok, conn, messages} -> consume(messages, conn, ref, max_bytes, deadline, response)
        {:error, _conn, error, _messages} -> {:error, network_reason(error)}
      end
    end
  end

  defp consume([], conn, ref, max_bytes, deadline, response),
    do: receive_response(conn, ref, max_bytes, deadline, response)

  defp consume([{:status, ref, status} | rest], conn, ref, max_bytes, deadline, response),
    do: consume(rest, conn, ref, max_bytes, deadline, %{response | status: status})

  # Nothing here speaks another protocol, so a switch is a failed call.
  defp consume([{:headers, ref, _headers} | _], _conn, ref, _max_bytes, _deadline, %{status: 101}),
       do: {:error, :connection_error}

  # An informational (1xx) reply comes before the final one: its headers are
  # skipped and never taken as the answer or as an acknowledgement.
  defp consume([{:headers, ref, _headers} | rest], conn, ref, max_bytes, deadline, response)
       when response.status in 100..199,
       do: consume(rest, conn, ref, max_bytes, deadline, %{response | status: nil})

  # Headers after the final ones are a chunked reply's trailers: the answer
  # keeps the final headers.
  defp consume([{:headers, ref, _trailers} | rest], conn, ref, max_bytes, deadline, response)
       when is_list(response.headers),
       do: consume(rest, conn, ref, max_bytes, deadline, response)

  defp consume([{:headers, ref, headers} | rest], conn, ref, max_bytes, deadline, response) do
    headers = Enum.map(headers, fn {key, value} -> {String.downcase(key), value} end)
    response = %{response | headers: headers}

    cond do
      response.status >= 300 and
          (response.status < 400 or response.status not in response.body_statuses) ->
        {:ok, finish(%{response | body: ""})}

      response.answer == :headers and response.status < 300 ->
        {:ok, finish(%{response | body: nil})}

      true ->
        consume(rest, conn, ref, max_bytes, deadline, response)
    end
  end

  defp consume([{:data, ref, chunk} | rest], conn, ref, max_bytes, deadline, response) do
    if byte_size(response.body) + byte_size(chunk) <= max_bytes do
      consume(rest, conn, ref, max_bytes, deadline, %{response | body: response.body <> chunk})
    else
      {:error, :too_large}
    end
  end

  defp consume([{:done, ref} | _], _conn, ref, _max_bytes, _deadline, response),
    do: {:ok, finish(response)}

  defp consume([{:error, ref, error} | _], _conn, ref, _max_bytes, _deadline, _response),
    do: {:error, network_reason(error)}

  defp consume([_ | rest], conn, ref, max_bytes, deadline, response),
    do: consume(rest, conn, ref, max_bytes, deadline, response)

  defp remaining(deadline), do: max(1, deadline - System.monotonic_time(:millisecond))

  defp network_reason(%Mint.TransportError{reason: :timeout}), do: :timeout
  defp network_reason(%Mint.TransportError{reason: {:tls_alert, _}}), do: :tls_error
  defp network_reason(_), do: :connection_error

  defp finish(response), do: Map.take(response, [:status, :headers, :body])

  defp result_status({:ok, %{status: status}}), do: status
  defp result_status(_), do: :error

  defp in_network?(ip, network, bits) do
    shift = 32 - bits
    Bitwise.bsr(ip_number(ip), shift) == Bitwise.bsr(ip_number(network), shift)
  end

  defp ip_number({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d
end
