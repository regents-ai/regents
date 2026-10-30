# Paper Pro Daily: scheduled publishing

A paper's existing `date` is its publication day in UTC. Save papers through the
existing release upload command as usual; future dates are accepted and remain
private on the website until **00:00:00 UTC on that date**.

For the folder upload format, the header uses `MM-DD-YYYY`, for example:

```yaml
date: "10-12-2026"
```

That entry becomes public on October 12, 2026 at 00:00:00 UTC. The original
`2026-10-12.md` filename format has the same meaning. A day may have several
papers. Uploading the same `paper_url` again for the same date replaces that
entry; a different `paper_url` adds another paper to the day. Today and past
dates are public immediately.

The folder header may also list the paper's own authors, which show under its
title when a day has several papers:

```yaml
authors: ["Ashish Vaswani", "Noam Shazeer"]
```

## Tags

Every paper is filed under one to three tags, listed in `Regents.PaperProDaily.Tag`:
Autoresearch, Swarms, Self-Improvement, Harnesses, Training, Memory, Evaluation,
Safety, Economics and Science. Both upload formats require them in the header:

```yaml
tags: [Swarms, Memory]
```

The Tags row at the top of the page narrows the list to the papers filed under any
chosen tag and keeps the choice in the address (`/paper-pro-daily?tags=Swarms,Memory`),
so a filtered list can be shared. While a tag is chosen, Copy Filtered as Markdown
copies only those papers. Each paper's Markdown, and the reading API, list its tags.

To file papers that are already published under other tags, write a YAML file that
maps each paper's id (from `/api/v1/reading/papers`) to its tags and run
`/app/bin/tag-papers <file>` on the machine. Every paper in the file is tagged, or
none is; an unknown id, a paper not yet public or a tag outside the list stops it.

## Several papers on one day

A day with one paper looks as it always has. A day with two or more opens with
one tile per paper across the top (its cover, the first 40 characters of its
title and its authors), and the first paper below. Choosing a tile shows that
paper in its place. On a phone, two papers sit side by side, three are
full-width rows, and four or more sit two to a row.

## Visibility

The Ash resource applies the UTC cutoff on every read, including the feed,
which loads six days at a time, the entire-page Markdown export and direct picture URLs. A future picture
returns the same 404 as a missing picture, with `Cache-Control: no-store` so a
cached miss cannot delay its release. The server clock is authoritative; browser
and database-session time zones do not select the publication day.

Connected pages refresh their feed and Markdown copy at the next UTC midnight,
resetting to the first six days so old offsets cannot skip or duplicate
days. Reloading or reconnecting also reads the current publication date.

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
reads, exact UTC midnight and offset handling, leap/year boundaries,
static and connected-page visibility, the refresh handler, and direct image URLs.
