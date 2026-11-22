# Card decks

The five founding fleets each have a deck made before the fleet was created:
Classic #1 has 1,024 cards, one for each of its Keys; Syndicate #1,
Accelerant #1 and Cascade #1 have 1,000 cards each; and the Regents Club has
1,998, one for each Regents Club Pass. A fleet anyone
creates gets its deck later, recorded on chain by the keeper. Keys past their
fleet's deck draw their own card from their own seed. With these rules, the
fleet's record on chain, its reveals and the deck file give every Key's card.

## A deck file

`<deck hash>.json`, where the deck hash is `keccak256` of the file's bytes
exactly as they are. The fleet's record on chain holds that hash and the
number of cards, fixed when the deck was recorded.

```json
{"fleet": "CLASSIC #1", "table": "0x…", "cards": ["0x…", "0x…", …]}
```

Cards are numbered from 0 in the order listed. A card is a 32-byte seed; its
eight traits are the ones the trait table `table` (in `../trait_tables`) gives
that seed, by the same draw every Key uses.

## Which card a Key gets

On a founding fleet, Key N gets card N − 1, the Nth card listed, for Keys 1 to
the deck's size. Nothing is drawn for them: the card is known from the deck file
as soon as the Key exists.

On a fleet anyone creates, Keys 1 to the deck's size are dealt in the order
they were revealed:

1. Take the fleet's reveals of Keys numbered 1 to the deck's size, in the order
   they were logged on chain: by block number, then by log index within the
   block. Each Key is revealed once, with its seed.
2. Start with the remaining cards `0, 1, 2, …, size − 1`, in that order.
3. For each reveal in turn, read its seed as a 256-bit unsigned number and let
   `n` be how many cards remain. The Key gets the card at position
   `seed mod n` in the remaining list, counting from 0. The last card in the
   list then moves into that position, and the list is one shorter.

No card is dealt twice, and the last Key within the deck gets the last card
left.

## Example

A deck of 10 cards on a fleet anyone creates, and seeds `keccak256("deal-1")` to
`keccak256("deal-10")`, revealed in that order, deals cards
`2, 6, 8, 5, 1, 4, 3, 7, 9, 0`. The site shows only the founding fleets, so it
deals by number alone (`Regents.Keyfleet.Keys.card_seed/2`).
