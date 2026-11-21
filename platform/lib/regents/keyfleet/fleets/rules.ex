defmodule Regents.Keyfleet.Fleets.Rules do
  @moduledoc """
  Each fleet's rules in plain words: how it prices its Keys and the terms
  every member joins under, with the numbers in them written the one way
  every page writes them.

  The fleet page and the open fleet directory say these the same way, so they
  are written once, here. The homepage says none of them; it only writes its
  numbers through `keys/1` and `grouped/1`.
  """

  # How each fleet prices its Keys and where a buyer's payment goes.
  @pricing %{
    "fibonacci_syndicate" =>
      "Keys come in levels of 2, 3, 5, 8 and on, each level 20% dearer than the one before, " <>
        "and new levels keep opening. 90% of what buyers pay goes to the fleet’s treasury " <>
        "as REGENT.",
    "fibonacci_cascade" =>
      "The same levels and prices, and new levels keep opening. When a level sells out, the " <>
        "holders of the level before it are paid back what their Keys cost.",
    "fleet_tech_classic" =>
      "1,024 Keys, from 10 USDC for the first to 100 USDC for the last. 90% of each sale " <>
        "goes to the fleet’s treasury as REGENT.",
    "fleet_tech_accelerant" =>
      "Up to 2,000 Keys, each 5% dearer than the one before. After the first Key, 70% of each " <>
        "sale goes to whoever holds the Key before it and 20% to the fleet’s treasury as REGENT.",
    "regents_club" =>
      "1,998 Keys, one for each Regents Club Pass, never sold. Key 1 goes to whoever holds " <>
        "Pass 1, Key 2 to Pass 2, and on."
  }

  @membership_terms [
    "The Key holders own the fleet. Each Key has one vote, and everything the fleet receives " <>
      "outside a Key sale, USDC included, goes to its treasury.",
    "10% of each Key sale stays USDC and goes to REGENT staking, once, and nothing from the " <>
      "treasury after.",
    "Once a day, anyone can release the Daily Treasury Slice to Keys. It shares from 0.1% to 2% of " <>
      "each token it covers equally among the Keys sold at least 2 days ago, at the rate the " <>
      "Keys vote for, starting at 0.5%. A token is shared only while the treasury holds at " <>
      "least 100 of it, or 0.05 ETH.",
    "A new Key waits 2 days before it can propose or vote. It is present on its own from " <>
      "day 2 to day 4; after that its holder marks it present, which lasts 48 hours. A Key " <>
      "away for longer keeps its part of every slice and can come back at any time.",
    "Every vote lasts 24 hours, and a vote can be changed until it closes. A proposal is " <>
      "approved when at least 60% of the Keys counted for it vote yes, rounded up, so one " <>
      "Key counted can approve it alone. The Keys counted are those present when it opened, " <>
      "and any Key that votes on it later. An approved proposal can be carried out for 48 " <>
      "hours after voting closes.",
    "For the first 7 days of sales, proposals can only change the fleet’s profile, the rate " <>
      "of its Daily Treasury Slice to Keys and who may edit the workspace. After that, approved " <>
      "proposals can spend everything in the treasury.",
    "A Key’s owner can issue shards of it to agents’ wallets, for 1 to 365 days. An agent " <>
      "with a shard can post in the rooms, work in the shared workspace and start rooms as " <>
      "the Key.",
    "While the Key’s agent voting is on, as it is unless its owner turns it off, an agent " <>
      "with a shard can also mark the Key present, vote, propose and cancel the Key’s " <>
      "proposals.",
    "An agent with a shard can claim the Key’s money, which is always paid to the wallet " <>
      "holding the Key. A shard never buys or moves Keys.",
    "When a Key changes hands, all its shards end. The new owner issues their own.",
    "Posts and workspace changes stay with whoever wrote them."
  ]

  @doc "How a fleet prices its Keys and where a buyer's payment goes."
  def pricing(fleet_id), do: Map.fetch!(@pricing, fleet_id)

  @doc "The terms every member of every fleet joins under, one sentence each."
  def membership_terms, do: @membership_terms

  @doc "A number of keys in words, such as `1 Key` or `1,771 Keys`."
  def keys(count), do: counted(count, "Key", "Keys")

  @doc "`count` things in words, such as `1 vote` or `1,024 votes`."
  def counted(1, one, _many), do: "1 #{one}"
  def counted(count, _one, many), do: "#{grouped(count)} #{many}"

  @doc "A whole number with its thousands separated by commas."
  def grouped(number), do: number |> Integer.to_string() |> RegentFormat.add_delimiters()
end
