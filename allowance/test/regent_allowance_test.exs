defmodule RegentAllowanceTest do
  # Not async: one test names a second site through the application environment.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias RegentAllowance.TestRepo
  alias RegentOpenAI.{Error, Reply, Speech, Transcript}

  @person "did:privy:person"

  setup do
    :ok = SQL.Sandbox.checkout(TestRepo)
  end

  test "a person with nothing recorded has spent nothing and is allowed" do
    assert Decimal.equal?(RegentAllowance.spent_today(@person), 0)
    assert RegentAllowance.allowed?(@person)
  end

  test "a reply, a transcript, spoken audio and a billed error are each recorded" do
    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("0.10", 1_000, 200, 50))

    assert :ok =
             RegentAllowance.record(@person, "gpt-4o-mini-transcribe", transcript("0.02"))

    assert :ok = RegentAllowance.record(@person, "gpt-4o-mini-tts", speech("0.03"))

    billed = %Error{reason: :invalid_json, usage: usage(10, 0, 5), cost_usd: Decimal.new("0.05")}
    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", billed)

    assert Decimal.equal?(RegentAllowance.spent_today(@person), Decimal.new("0.20"))

    assert [
             %{
               "site" => "test",
               "model" => "gpt-5.6-terra",
               "input_tokens" => 1_000,
               "cached_input_tokens" => 200,
               "output_tokens" => 50
             }
             | _rest
           ] = rows()

    assert length(rows()) == 4
  end

  test "an error OpenAI did not bill records nothing" do
    unbilled = %Error{reason: {:transport, "timeout"}}

    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", unbilled)
    assert rows() == []
  end

  test "the allowance counts every site together" do
    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("1.20"))

    Application.put_env(:regent_allowance, :site, "other")
    on_exit(fn -> Application.put_env(:regent_allowance, :site, "test") end)

    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("0.80"))

    assert Enum.map(rows(), & &1["site"]) |> Enum.sort() == ["other", "test"]
    assert Decimal.equal?(RegentAllowance.spent_today(@person), Decimal.new("2.00"))
    refute RegentAllowance.allowed?(@person)
  end

  test "a person is allowed until today's spend reaches $2.00" do
    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("1.99"))
    assert RegentAllowance.allowed?(@person)

    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("0.01"))
    refute RegentAllowance.allowed?(@person)

    # The last call of the day may finish over; it is still recorded.
    assert :ok = RegentAllowance.record(@person, "gpt-5.6-terra", reply("0.40"))
    assert Decimal.equal?(RegentAllowance.spent_today(@person), Decimal.new("2.40"))
  end

  test "the day starts at midnight UTC" do
    midnight = DateTime.new!(Date.utc_today(), ~T[00:00:00.000000], "Etc/UTC")

    insert_at(DateTime.add(midnight, -1, :microsecond), "1.50")
    insert_at(midnight, "0.25")

    assert Decimal.equal?(RegentAllowance.spent_today(@person), Decimal.new("0.25"))
  end

  test "another person's spend does not count" do
    assert :ok = RegentAllowance.record("did:privy:someone-else", "gpt-5.6-terra", reply("2.00"))

    assert Decimal.equal?(RegentAllowance.spent_today(@person), 0)
    assert RegentAllowance.allowed?(@person)
  end

  test "migrating again changes nothing" do
    assert [] = RegentAllowance.Migrator.up(TestRepo)
  end

  defp reply(cost, input \\ 100, cached \\ 0, output \\ 20) do
    %Reply{
      text: "ok",
      response_id: "resp_1",
      model: "gpt-5.6-terra",
      usage: usage(input, cached, output),
      cost_usd: Decimal.new(cost)
    }
  end

  defp transcript(cost),
    do: %Transcript{
      text: "hello",
      model: "gpt-4o-mini-transcribe",
      usage: usage(30, 0, 4),
      cost_usd: Decimal.new(cost)
    }

  defp speech(cost),
    do: %Speech{
      audio: <<>>,
      content_type: "audio/mpeg",
      model: "gpt-4o-mini-tts",
      usage: usage(12, 0, 300),
      cost_usd: Decimal.new(cost)
    }

  defp usage(input, cached, output),
    do: %{input_tokens: input, cached_input_tokens: cached, output_tokens: output}

  defp insert_at(inserted_at, cost) do
    SQL.query!(
      TestRepo,
      """
      INSERT INTO regent_allowance.openai_calls
        (privy_user_id, site, model, input_tokens, cached_input_tokens, output_tokens, cost_usd, inserted_at)
      VALUES ($1, 'test', 'gpt-5.6-terra', 1, 0, 1, $2, $3)
      """,
      [@person, Decimal.new(cost), inserted_at]
    )
  end

  defp rows do
    %{columns: columns, rows: rows} =
      SQL.query!(TestRepo, "SELECT * FROM regent_allowance.openai_calls ORDER BY inserted_at")

    Enum.map(rows, &(columns |> Enum.zip(&1) |> Map.new()))
  end
end
