defmodule RegentSprites.Output do
  @moduledoc """
  What a command run on a machine printed, and how it ended.

  Sprites marks each piece of output with one byte (1 for standard output, 2 for
  standard error) and ends with byte 3 and the exit code, without saying how long
  each piece is. Output that itself holds bytes 1, 2 or 3 cannot be told apart from
  those marks, so a command whose output may be binary should print it as base64,
  as `RegentSprites.read_file/2` does.
  """

  @enforce_keys [:exit_code, :stdout, :stderr]
  defstruct [:exit_code, :stdout, :stderr]

  @type t :: %__MODULE__{
          exit_code: non_neg_integer(),
          stdout: binary(),
          stderr: binary()
        }

  @stdout 1
  @stderr 2
  @exit 3

  @doc false
  @spec from_frames(binary()) :: {:ok, t()} | :error
  def from_frames(body) when byte_size(body) >= 2 do
    size = byte_size(body) - 2

    case body do
      <<frames::binary-size(^size), @exit, code>>
      when frames == "" or binary_part(frames, 0, 1) in [<<@stdout>>, <<@stderr>>] ->
        {stdout, stderr} = split(frames, nil, [], [])
        {:ok, %__MODULE__{exit_code: code, stdout: stdout, stderr: stderr}}

      _body ->
        :error
    end
  end

  def from_frames(_body), do: :error

  defp split(<<>>, _stream, stdout, stderr) do
    {stdout |> Enum.reverse() |> IO.iodata_to_binary(),
     stderr |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp split(<<marker, rest::binary>>, _stream, stdout, stderr)
       when marker in [@stdout, @stderr] do
    split(rest, marker, stdout, stderr)
  end

  defp split(frames, stream, stdout, stderr) do
    {chunk, rest} =
      case :binary.match(frames, [<<@stdout>>, <<@stderr>>]) do
        {at, 1} -> {binary_part(frames, 0, at), binary_part(frames, at, byte_size(frames) - at)}
        :nomatch -> {frames, <<>>}
      end

    case stream do
      @stdout -> split(rest, stream, [chunk | stdout], stderr)
      @stderr -> split(rest, stream, stdout, [chunk | stderr])
    end
  end
end
