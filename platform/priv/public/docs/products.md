## List

`GET /api/v1/products` lists Keyfleet, Autolaunch, Patchbay, Techtree and Cloak, in the order the site lists them, with each one's summary and links.

```sh
curl --fail '{{origin}}/api/v1/products'
```

## One product

`GET /api/v1/products/{slug}` returns everything that product's page on Regents shows. The four slugs above are available here. Cloak is documented on its [desktop app guide]({{origin}}/docs/cloak). An unknown slug answers `404`.

```sh
curl --fail '{{origin}}/api/v1/products/techtree'
```

## Other surfaces

In a browser that supports WebMCP, use `regents_products` and `regents_product`. All Regents Labs products live under `{{origin}}` with unified docs under `/docs`: [Cloak]({{origin}}/docs/cloak) ([Architecture]({{origin}}/docs/cloak/reference) · [Wallet Security]({{origin}}/docs/cloak/wallets)), [Techtree]({{origin}}/docs/techtree), [Keyfleet]({{origin}}/docs/keyfleet), [Autolaunch]({{origin}}/docs/autolaunch), and [Patchbay]({{origin}}/docs/patchbay).
