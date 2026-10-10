# Articles admin editor — local, awaiting publication authority

Done criteria: authorized admins can publish a complete Markdown article with title,
date, ordered author/X pairs and cover; the gallery and detail show it correctly;
other visitors and ended sessions cannot use the editor.

## Implemented

- `/admin/articles`, with an admin-only New Article link in `/articles`.
- Uses `Regents.Credits.admin?/1` and the existing `REGENT_CREDITS_ADMINS` setting.
  Sean explicitly selected this list. Production read-only inspection found one
  configured Privy account, linked to wallet 0x0cb27e883e207905ad2a94f9b6ef0c7a99223c37,
  without a display name. No admin setting was changed remotely.
- Markdown, title, date, 1–20 author names/X profiles, PNG/JPEG/WebP cover up to
  1 MB, optional cover description. Handles normalize to HTTPS X profile URLs.
- Ash action `publish` authorizes a normal Human actor by freshly reading its
  account. HTTP/mount/navigation/event guards and current session leases protect
  the editor; ended sessions withdraw the editor and show a clear notice.
- New articles get unique UUID slugs, create rather than upsert, and record the
  publisher account id. Existing operator folder uploads remain available.
- Additive migration 20261010053235 adds `authors` (empty by default for existing
  posts) and `published_by`. Publication filters still hide future articles/covers.
- Shared `Regent.Blog.article` renders each author's X link, falling back to the
  single-author fields for older posts. Template reference:
  `repos/ash-template/docs/article-authors-reference.md` (new, scoped local file).

## Verified

- Scoped Elixir formatting, compilation with warnings treated as errors, asset
  build, generated route handoff and whitespace checks passed.
- Canonical shared component `mix check`: 36 existing checks passed. No new suite
  or product-mirroring tests were added.
- Browser local fixture: add/remove authors keeps the other inputs, wrong X URL
  and missing cover are rejected, uploaded cover stays through field correction,
  complete two-author submission saves, gallery/detail/cover work, both X links
  are displayed. Mobile fields were corrected to fit 390px.
- Anonymous/member HTTP editor requests return 404. Anonymous, System and ordinary
  Human actors cannot use `publish`. Future article and cover are hidden; publisher
  id is recorded. Shared renderer strips script/javascript Markdown.
- Actual mounted-session revocation: a fully prepared submission was blocked and
  displayed the access-ended notice; row count stayed 3 and refused title count 0.
- Independent security review by `/root/agent_access_security`: no findings.
  Bounded temporary uploads may finish after revocation, but publication remains
  protected by the fresh session and policy checks.
- Local additive migration applied to both the private editor fixture DB and the
  existing owned public preview DB, preserving existing content. Existing preview
  `/articles` and `/keyfleet` return 200; actual Privy app meta remains nonempty.

## Source and previews

- Authoring checkout: `worktrees/regents/paper-pro-daily`, branch
  `rg/unified-agent-access`. Preserve other pending account/Credits/Points changes.
- Canonical design-system authoring ref `cdef167ce2130d4d8d97db81d89fd9461bed416f`
  on `rg/articles-authors-20261010`, atop fe81. Consumer uses this locally.
- Narrow shared release variant `b46405a1fb03d28af4c9787613ede832091e4267` on
  `rg/articles-authors-release-20261010`, atop current live pin 24f3. Exactly the
  three author-display contract/component files; no account-status rollout.
- Canonical primary design-system retains the corresponding owned three-file
  working diff; its unrelated CONSUMERS/artwork changes were preserved.
- No new checkout/clone. Local Git refs use a separate index, leaving unrelated
  working changes untouched. No push, deploy, production migration or settings
  write occurred for this feature.
- Actual configured public preview port 4016 was restarted by its owner after the
  shared pin changed, session 71330, `/tmp/regents-literature-preview.exs`.
- Separate editor fixture port 4017, session 31050,
  `/tmp/regents-article-admin-preview.exs`, guarded localhost
  `regents_articles_editor_dev`. Actual Privy settings are loaded and meta checked;
  fixture sign-in uses the standard SessionAuthority and its own cookie key, with
  a temporary fixture-only provider bridge. The wrapper is not product source.
  `/__fixture/admin` starts the local admin fixture; `/__fixture/revoke` revokes it.
- Screenshots under the task visualization directory `articles-admin/`:
  editor.png, editor-cover.png, mobile-cover.png. Browser tab 19 is the deliverable.

## Next consequential action

Publishing requires Sean's explicit authority for this feature. After approval,
re-read live version, assemble only this patch atop that version, retain live
elixir-utils pin, use the narrow shared release variant, validate the integrated
release, push the owned refs and apply only the Articles migration. Use Depot
for remote build; do not deploy the full authoring branch. Last known live source
533003581205eaf03c44cb935bfb50451ff30d2a, image a59106dd...642f7, one healthy web
machine 83d1d90f6d0018. Do not upload local fixture posts to production.
