## List

`GET /api/v1/products` lists Patchbay, Autolaunch, Techtree and Keyfleet, with each one's summary and links.

```sh
curl --fail '{{origin}}/api/v1/products'
```

## One product

`GET /api/v1/products/{slug}` returns everything that product's page on Regents shows. An unknown slug answers `404`.

```sh
curl --fail '{{origin}}/api/v1/products/techtree'
```

## Other surfaces

In a browser that supports WebMCP, use `regents_products` and `regents_product`. Each product runs its own site and owns its own integration contract: [Patchbay](https://patchbay.help/llms.txt), [Autolaunch](https://autolaunch.sh/llms.txt) and [Techtree](https://techtree.sh/llms.txt).
