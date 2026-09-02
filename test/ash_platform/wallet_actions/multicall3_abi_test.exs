defmodule AshPlatform.WalletActions.Multicall3AbiTest do
  use ExUnit.Case, async: true

  alias AshPlatform.WalletActions.Abi

  @staking "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @regent "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  @wallet "0x1111111111111111111111111111111111111111"
  @paused "0x5c975abb"
  @balance_of "0x70a08231"

  @zero_word String.duplicate("0", 64)

  test "AGGREGATE3_SELECTOR: the pinned selector is Keccak-256 of the pinned signature" do
    assert Abi.aggregate3_signature() == "aggregate3((address,bool,bytes)[])"

    assert Abi.aggregate3_selector() ==
             Abi.topic0(Abi.aggregate3_signature()) |> String.slice(0, 10)

    assert Abi.aggregate3_selector() == "0x82ad56cb"
  end

  # Hand-computed against the ABI specification, word by word:
  #   [0] 0x20  offset of the one dynamic argument, the call array
  #   [1] 0x01  array length
  #   [2] 0x20  offset of element 0, from the first word after the length
  #   [3]       target, left-padded into a word
  #   [4] 0x00  allowFailure, which is false on every sub-call
  #   [5] 0x60  offset of callData inside the element, three words in
  #   [6] 0x04  callData length in bytes
  #   [7]       callData, right-padded to a whole word
  test "ONE_CALL_ENCODING: one sub-call encodes to the exact hand-computed calldata" do
    expected =
      "0x82ad56cb" <>
        word(0x20) <>
        word(0x01) <>
        word(0x20) <>
        address_word(@staking) <>
        word(0x00) <>
        word(0x60) <>
        word(0x04) <> "5c975abb" <> String.duplicate("0", 56)

    assert Abi.encode_aggregate3([{@staking, @paused}]) == expected
  end

  # Two sub-calls, the second carrying 36 bytes so the tail padding is proved.
  # Element 0 occupies five words (160 bytes) and element 1 six (192 bytes), so
  # the two head offsets are 0x40 and 0x40 + 0xa0 = 0xe0.
  test "TWO_CALL_ENCODING: element offsets follow the exact widths of what precedes them" do
    balance_of_data = @balance_of <> String.slice(address_word(@wallet), 0, 64)

    expected =
      "0x82ad56cb" <>
        word(0x20) <>
        word(0x02) <>
        word(0x40) <>
        word(0xE0) <>
        address_word(@staking) <>
        word(0x00) <>
        word(0x60) <>
        word(0x04) <>
        ("5c975abb" <> String.duplicate("0", 56)) <>
        address_word(@regent) <>
        word(0x00) <>
        word(0x60) <>
        word(0x24) <>
        ("70a08231" <> String.duplicate("0", 24) <> String.duplicate("1", 32)) <>
        String.duplicate("1", 8) <> String.duplicate("0", 56)

    assert Abi.encode_aggregate3([{@staking, @paused}, {@regent, balance_of_data}]) == expected
  end

  test "ALLOW_FAILURE_IS_FALSE: no encoded sub-call ever sets the allowFailure word" do
    encoded = Abi.encode_aggregate3([{@staking, @paused}, {@regent, @paused}])

    # Counting words after the selector: 0 array offset, 1 length, 2-3 the two
    # element offsets, 4 target, 5 allowFailure, 6 data offset, 7 data length,
    # 8 data, 9 target, 10 allowFailure.
    assert String.slice(encoded, 2 + 8 + 5 * 64, 64) == @zero_word
    assert String.slice(encoded, 2 + 8 + 10 * 64, 64) == @zero_word
  end

  # Hand-computed the same way: two results, the first returning one word and
  # the second returning nothing. Element 0 is four words (0x80), so the head
  # offsets are 0x40 and 0xc0.
  test "RESULT_DECODING: an exact hand-computed response decodes to its two payloads" do
    assert Abi.decode_aggregate3(two_results(), 2) == {:ok, ["0x" <> @zero_word, "0x"]}
  end

  test "RESULT_COUNT: a response declaring a different number of results is refused" do
    assert Abi.decode_aggregate3(two_results(), 1) == :error
    assert Abi.decode_aggregate3(two_results(), 3) == :error
  end

  test "UNSUCCESSFUL_ENTRY: allowFailure was false, so an unsuccessful entry is a contradiction" do
    refused =
      replace_word(two_results(), 4, word(0x00))

    assert Abi.decode_aggregate3(refused, 2) == :error
  end

  test "OFFSET_VALIDATION: an offset that leaves the payload or overlaps the heads is refused" do
    # An element offset pointing back into the head words themselves.
    assert Abi.decode_aggregate3(replace_word(two_results(), 2, word(0x00)), 2) == :error

    # An element offset past the end of the response.
    assert Abi.decode_aggregate3(replace_word(two_results(), 3, word(0x2000)), 2) == :error

    # An offset that is not word-aligned.
    assert Abi.decode_aggregate3(replace_word(two_results(), 2, word(0x41)), 2) == :error

    # The top-level argument offset pointing outside the payload.
    assert Abi.decode_aggregate3(replace_word(two_results(), 0, word(0x2000)), 2) == :error

    # A declared byte length wider than the entry it sits in: without a bound
    # taken from the next entry, this would read that entry's bytes instead.
    assert Abi.decode_aggregate3(replace_word(two_results(), 6, word(0x40)), 2) == :error

    # Two entries claiming the same start, and a pair given out of order. Both
    # are refused, but neither of these isolates the ordering rule: an entry
    # that starts where the next one does is empty, and this out-of-order pair
    # points at bytes that do not fill an entry either way.
    assert Abi.decode_aggregate3(replace_word(two_results(), 3, word(0x40)), 2) == :error
    assert Abi.decode_aggregate3(replace_word(two_results(), 2, word(0x100)), 2) == :error

    # A truncated response, one word short of the last entry.
    truncated = String.slice(two_results(), 0, byte_size(two_results()) - 64)
    assert Abi.decode_aggregate3(truncated, 2) == :error
  end

  # A response that is well formed in every other respect: both starts are
  # word-aligned and inside the body, both entries decode, and the body ends
  # exactly where the last one does. The only thing wrong with it is that the
  # second entry starts before the first, which reads one entry's bytes twice
  # and accepts a layout no canonical encoder produces. Nothing but the
  # ascending rule refuses it.
  test "ASCENDING_ENTRIES: entries given out of order are refused, never reordered" do
    # The same entry, given once and in order, decodes: nothing in its bytes is
    # malformed.
    assert Abi.decode_aggregate3(one_result(), 1) == {:ok, ["0x" <> @zero_word]}

    assert Abi.decode_aggregate3(descending_results(), 2) == :error
  end

  test "MALFORMED_RESPONSE: anything but exactly the encoded results is refused" do
    for value <- ["0x", "0xzz", "0x1234", two_results() <> word(0x00), "not hex"] do
      assert Abi.decode_aggregate3(value, 2) == :error
    end
  end

  defp two_results do
    "0x" <>
      word(0x20) <>
      word(0x02) <>
      word(0x40) <>
      word(0xC0) <>
      word(0x01) <>
      word(0x40) <>
      word(0x20) <>
      word(0x00) <>
      word(0x01) <>
      word(0x40) <> word(0x00)
  end

  # One result, laid out canonically: the array one word in, one element, and
  # that element four words after the head word that points at it.
  defp one_result, do: "0x" <> word(0x20) <> word(0x01) <> word(0x20) <> entry()

  # The same one entry, with two head words pointing at it in the wrong order:
  # element 0 starts at 0xc0, where the body ends, and element 1 at 0x40, where
  # the entry begins. Element 0 is then bounded by element 1's start and element
  # 1 by the end of the body, so both land on the same four well-formed words.
  defp descending_results,
    do: "0x" <> word(0x20) <> word(0x02) <> word(0xC0) <> word(0x40) <> entry()

  # `(true, <one zero word>)`, four words wide.
  defp entry, do: word(0x01) <> word(0x40) <> word(0x20) <> word(0x00)

  defp replace_word("0x" <> hex, index, replacement) do
    "0x" <>
      String.slice(hex, 0, index * 64) <>
      replacement <> String.slice(hex, (index + 1) * 64, byte_size(hex))
  end

  defp word(value),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

  defp address_word(address),
    do: address |> String.trim_leading("0x") |> String.pad_leading(64, "0")
end
