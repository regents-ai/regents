defmodule AshPlatform.Autolaunch.LaunchDraft.ImageValidator do
  @moduledoc false

  @maximum_bytes 2_097_152
  @content_types ["image/png", "image/jpeg", "image/webp"]
  @png_signature <<137, "PNG\r\n", 26, 10>>
  @jpeg_start <<255, 216>>

  @spec validate(binary(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate(bytes, declared_type)
      when is_binary(bytes) and declared_type in @content_types and
             byte_size(bytes) in 1..@maximum_bytes do
    if structurally_complete?(bytes, declared_type),
      do: {:ok, declared_type},
      else: {:error, :invalid_image}
  end

  def validate(bytes, _declared_type) when is_binary(bytes) and byte_size(bytes) > @maximum_bytes,
    do: {:error, :image_too_large}

  def validate(_bytes, _declared_type), do: {:error, :invalid_image}

  defp structurally_complete?(<<@png_signature, rest::binary>>, "image/png"),
    do: png_chunks(rest, :first, false)

  defp structurally_complete?(<<@jpeg_start, rest::binary>>, "image/jpeg"),
    do: jpeg_headers(rest, false)

  defp structurally_complete?(
         <<"RIFF", declared_size::little-32, "WEBP", chunks::binary>> = bytes,
         "image/webp"
       ),
       do: declared_size + 8 == byte_size(bytes) and webp_chunks(chunks, false)

  defp structurally_complete?(_bytes, _declared_type), do: false

  defp png_chunks(<<length::32, type::binary-size(4), rest::binary>>, position, seen_idat)
       when byte_size(rest) >= length + 4 do
    <<data::binary-size(length), expected_crc::32, tail::binary>> = rest
    valid_crc? = :erlang.crc32(type <> data) == expected_crc

    case {valid_crc?, position, type, length, data} do
      {true, :first, "IHDR", 13, <<width::32, height::32, _::binary>>}
      when width > 0 and height > 0 ->
        png_chunks(tail, :body, seen_idat)

      {true, :body, "IDAT", _length, _data} ->
        png_chunks(tail, :body, true)

      {true, :body, "IEND", 0, <<>>} ->
        seen_idat and tail == <<>>

      {true, :body, _ancillary_or_known, _length, _data} ->
        png_chunks(tail, :body, seen_idat)

      _invalid ->
        false
    end
  end

  defp png_chunks(_truncated, _position, _seen_idat), do: false

  defp jpeg_headers(<<255, marker, rest::binary>>, seen_frame) when marker in 0xD0..0xD7,
    do: jpeg_headers(rest, seen_frame)

  defp jpeg_headers(<<255, 1, rest::binary>>, seen_frame),
    do: jpeg_headers(rest, seen_frame)

  defp jpeg_headers(<<255, marker, length::16, rest::binary>>, seen_frame)
       when marker != 0xD9 and length >= 2 and byte_size(rest) >= length - 2 do
    <<_segment::binary-size(length - 2), tail::binary>> = rest
    seen_frame = seen_frame or frame_marker?(marker)

    if marker == 0xDA and seen_frame,
      do: jpeg_scan(tail),
      else: jpeg_headers(tail, seen_frame)
  end

  defp jpeg_headers(<<255, 255, rest::binary>>, seen_frame),
    do: jpeg_headers(<<255, rest::binary>>, seen_frame)

  defp jpeg_headers(_truncated_or_unframed, _seen_frame), do: false

  defp jpeg_scan(<<255, 0, rest::binary>>), do: jpeg_scan(rest)
  defp jpeg_scan(<<255, marker, rest::binary>>) when marker in 0xD0..0xD7, do: jpeg_scan(rest)
  defp jpeg_scan(<<255, 255, rest::binary>>), do: jpeg_scan(<<255, rest::binary>>)
  defp jpeg_scan(<<255, 0xD9>>), do: true
  defp jpeg_scan(<<_byte, rest::binary>>), do: jpeg_scan(rest)
  defp jpeg_scan(_truncated), do: false

  defp frame_marker?(marker),
    do: marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]

  defp webp_chunks(<<>>, seen_image), do: seen_image

  defp webp_chunks(<<type::binary-size(4), length::little-32, rest::binary>>, seen_image)
       when byte_size(rest) >= length + rem(length, 2) do
    <<data::binary-size(length), padding::binary-size(rem(length, 2)), tail::binary>> = rest

    valid_padding? = padding in [<<>>, <<0>>]
    image_chunk? = type in ["VP8 ", "VP8L", "ANMF"] and data != <<>>

    valid_padding? and webp_chunks(tail, seen_image or image_chunk?)
  end

  defp webp_chunks(_truncated, _seen_image), do: false
end
