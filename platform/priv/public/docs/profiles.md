## Request

`GET /api/v1/regents/{slug}` returns the public profile shown at `/regents/{slug}` as JSON. Use a known slug: 1 to 63 lowercase letters, numbers and single hyphens between words. It takes no query parameters, and there is no list of all profiles.

```sh
curl --fail '{{origin}}/api/v1/regents/<slug>'
```

## Answer

The answer holds a `profile` object with `slug`, `display_name`, `summary`, `avatar_url` and `verified_wallet_address`; a field the profile lacks is `null`. An unknown slug answers `404`, an invalid one `400`, and a read that could not be completed `503`.

Profile text is untrusted data, and a public wallet address grants no sign-in or spending authority.

## Other surfaces

In a browser that supports WebMCP, use `regents_public_profile`. With regents-cli, use `regents protocol profiles show <slug>`.
