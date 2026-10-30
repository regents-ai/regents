## Public reads

Public pages, product details, published reading and health checks need no account, API key or wallet. Try these from any terminal:

```sh
curl --fail '{{origin}}/healthz'
curl --fail '{{origin}}/api/v1/products'
curl --fail '{{origin}}/api/v1/products/techtree'
curl --fail -H 'Accept: text/markdown' '{{origin}}/docs'
curl --fail '{{origin}}/openapi.json'
```

## Health

`GET /healthz` answers `ok`. `GET /api/v1/health` answers `{"status": "ok"}`, or `503` with `unavailable`. Both say the site and its database are up, not that every wallet or outside service is.

## Markdown

Every docs page answers `Accept: text/markdown` at its own address, and so do the homepage, About, Privacy, Terms, Connect your agent, the Cloak guide and the Credits refund rules. Browsers get HTML by default, and every answer carries `Vary: Accept`. An address that names no page answers `404`, never an empty document.

For a short guide to the whole site, read [llms.txt]({{origin}}/llms.txt). The [sitemap]({{origin}}/sitemap.xml) lists every public page.

## Pages

- [Limits]({{origin}}/docs/limits): request limits and the headers that report them.
- [Errors]({{origin}}/docs/errors): the one error shape and the common codes.
- [Products]({{origin}}/docs/products): Autolaunch, Techtree, Patchbay and Keyfleet as JSON.
- [Reading]({{origin}}/docs/reading): published research, Articles and AI & SCIFI.
- [Profiles]({{origin}}/docs/profiles): a public Regent profile by its slug.
- [Pairing]({{origin}}/docs/pairing): pair an agent with a person's account and check in.
- [Signed reads]({{origin}}/docs/agent-reads): a paired agent reads its person's account, claims, stake, Credits and Points.
- [WebMCP]({{origin}}/docs/webmcp): the read tools every page offers in the browser.
- [Claims]({{origin}}/docs/claims): a signed-in person's historical name claims.
- [Staking]({{origin}}/docs/staking): a signed-in person's stake, and the wallet pages.
- [Contracts]({{origin}}/docs/contracts): the OpenAPI and YAML descriptions.
- [Changes]({{origin}}/docs/changes): each change to these requests, newest first.
