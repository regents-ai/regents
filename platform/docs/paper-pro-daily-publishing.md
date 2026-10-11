# Paper Pro Daily: scheduled publishing

A paper's existing `date` is its publication day in UTC. Save papers through the
existing release upload command as usual; future dates are accepted and remain
private on the website until **00:00:00 UTC on that date**.

For the folder upload format, the header uses `MM-DD-YYYY`, for example:

```yaml
date: "10-12-2026"
```

That entry becomes public on October 12, 2026 at 00:00:00 UTC. The original
`2026-10-12.md` filename format has the same meaning. The existing one-paper-per-day
rule is unchanged: uploading another paper for the same date replaces that entry.
Today and past dates are public immediately.

## Visibility

The Ash resource applies the UTC cutoff on every read, including the paginated
feed, the entire-page Markdown export and direct picture URLs. A future picture
returns the same 404 as a missing picture, with `Cache-Control: no-store` so a
cached miss cannot delay its release. The server clock is authoritative; browser
and database-session time zones do not select the publication day.

Connected pages refresh their feed and Markdown copy at the next UTC midnight,
resetting to the first page so old pagination offsets cannot skip or duplicate
papers. Reloading or reconnecting also reads the current publication date.

Publication does not rewrite the row and requires no cron job, worker, migration
or per-paper deployment. The code change itself must be deployed before relying
on this behavior. It does not make an independently shared ChatGPT answer, source
paper, previously cached content or externally hosted copy private.

## Verification

From `platform/`, with the normal prepared local test database and a unique
`MIX_TEST_PARTITION`, run:

```sh
MIX_TEST_PARTITION=_paper_utc mix test test/regents/paper_pro_daily_test.exs test/regents_web/paper_pro_daily_live_test.exs
MIX_TEST_PARTITION=_paper_utc mix precommit
```

The regression tests cover early insertion and replacement, today/past/future
reads, pagination, exact UTC midnight and offset handling, leap/year boundaries,
static and connected-page visibility, the refresh handler, and direct image URLs.
