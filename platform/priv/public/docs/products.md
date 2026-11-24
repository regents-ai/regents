## List

`GET /api/v1/products` lists Keyfleet, Autolaunch, Patchbay, Techtree and Cloak, in the order the site lists them, with each one's summary and links.

```sh
curl --fail '{{origin}}/api/v1/products'
```

## One product

`GET /api/v1/products/{slug}` returns everything that product's page on Regents shows. An unknown slug answers `404`.

```sh
curl --fail '{{origin}}/api/v1/products/techtree'
```

## Other surfaces

In a browser that supports WebMCP, use `regents_products` and `regents_product`. Each web product owns its integration contract: [Keyfleet]({{origin}}/keyfleet/agents.md), [Autolaunch]({{origin}}/autolaunch/agents.md), [Patchbay]({{origin}}/patchbay/agents.md) and [Techtree]({{origin}}/techtree/agents.md). For [Cloak]({{origin}}/cloak) (native macOS app), request `{{origin}}/cloak`, `{{origin}}/cloak/install`, or `{{origin}}/docs/cloak/reference` with `Accept: text/markdown`.
