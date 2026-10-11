# Articles

Articles is the first tab under Reading at `/articles`. Each post starts as a folder,
then is saved in the database. New posts need no site release after this feature
is deployed. The previous `/blog` addresses redirect to `/articles`.

## Folder format

```text
blog/my-post/
  post.md
  cover.png
```

Use exactly one `cover.png`, `cover.jpg`, `cover.jpeg` or `cover.webp`, at most
1 MB. The cover is saved with the post; no external image URL is required.

`post.md` starts with YAML metadata, followed by the complete Markdown text:

```markdown
---
title: "A clear post title"
description: "A short description for the gallery."
date: "10-09-2026"
author: "Your name"
author_x: "https://x.com/your_handle"
cover_alt: "Describe what the cover shows."
draft: true
---

The post text goes here.

## A section

Markdown headings, lists, tables, code and LaTeX are supported.
```

Required: title, date, author, author_x and cover_alt. Description is optional.
The date accepts MM-DD-YYYY or YYYY-MM-DD. `author_x` is a full HTTPS X profile
URL, following the existing blog byline format. `draft` defaults to false.
The folder name is the URL slug; an optional `slug` overrides it. Slugs use
lowercase letters, digits and single hyphens, up to 63 characters.

Drafts and future-dated posts stay out of the gallery and return 404 for both
the post and cover. Publication dates use UTC, as the previous catalog did.
Posts sort newest first; same-day posts sort by slug. Multiple posts per day
are allowed. Markdown is preserved; raw HTML never executes.

## Check and upload

From `platform/`, check a folder without saving it:

```sh
mix regents.blog.check ../blog/my-post
```

The operator uploads the folder to the chosen machine, then runs:

```sh
/app/bin/put-post /tmp/my-post
```

This saves or replaces the post with that slug. Production uploads and
replacements require Sean's applicable approval. Invalid metadata, empty text,
missing or ambiguous covers and files over 1 MB are refused before saving.

The gallery shows the cover, title, author, date and description. Selecting a
card opens the complete post, with a contents list and a Back to Articles link.
Updating the same slug preserves its identity and refreshes the cover address.

`example-post/` is an unpublished folder template. The old root-level example
and `images/` remain as historical authoring files; the live Articles page no longer
reads root-level Markdown at compile time.
