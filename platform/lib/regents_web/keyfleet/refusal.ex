defmodule RegentsWeb.Keyfleet.Refusal do
  @moduledoc """
  The JSON answer to a request the site refuses:
  `{"error": {"code", "message", "hint"}}`. `code` is stable and meant for
  programs; `message` says what went wrong and `hint` what to do next, both in
  plain words. Each code has one message and one hint, kept here.

  A workspace refusal is answered by `RegentsWeb.Keyfleet.AgentGraphController`, with
  the workspace's own words and its `details` in the same object. An error no
  route answers itself is `RegentsWeb.Keyfleet.ErrorJSON`'s.
  """

  # Said after where to look, at every address no agent operation has: the
  # likeliest sender of one is a tool made for an earlier site.
  @older_sender "If a command-line tool or a saved tool list sent this, it is older than the " <>
                  "site: install regents-cli again with the line /agents.md gives, or read " <>
                  "/capabilities.json again."

  @refusals %{
    # Signed agent requests, and browser sign-in.
    "unauthorized" =>
      {"The sign-in on this request couldn't be confirmed.",
       "Sign in again, then send the request again."},
    "smart_wallet_on_ethereum" =>
      {"A smart wallet signs in to this site on Base, where the Keys are, not on Ethereum.",
       "Run siwa_agent.py use-wallet again with the same address and signer, adding --chain base --force, then send the request again."},
    "duplicate_proof" =>
      {"A signature header was sent more than once.",
       "Sign the request again with your agent key, sending each header once."},
    "unsupported_query" =>
      {"A signed request here takes no query string.",
       "Put what the request asks for in its signed JSON body, then send it again."},
    "operation_unknown" =>
      {"There is no agent operation at this address.",
       "/docs lists each operation with its method and address: lowercase, with no trailing slash. " <>
         @older_sender},
    "method_not_allowed" =>
      {"This operation takes another method.",
       "Send it with the method the Allow header names, signed over that method."},
    "json_required" =>
      {"A signed request here carries a JSON body, or none.",
       "Send a POST with content-type: application/json and a JSON body, {} when there is nothing to say. Send a GET with no body."},
    "siwa_request_failed" =>
      {"The sign-in service could not be reached.", "Try again in a moment."},
    "feed_full" =>
      {"This site has as many feeds open as it can hold right now.", "Try again in a minute."},
    "feed_unavailable" =>
      {"The events your feed missed can't be read right now.",
       "Send the same request again in a moment."},
    "request_too_large" =>
      {"The request body is larger than this operation takes.",
       "Send a shorter body. /docs gives each operation's limit."},
    "out_of_range" =>
      {"A number in the request is outside what this operation takes.",
       "Check the numbers against /docs, then send the request again."},
    "invalid_request" =>
      {"The request doesn't fit this operation.",
       "Check the body against /docs, then send it again."},
    "invalid_cursor" =>
      {"That history cursor is invalid.",
       "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."},

    # The site before it opens, and the fleets.
    "not_open_yet" =>
      {"This part of the site isn't open yet.",
       "Wait the number of seconds in Retry-After, then send the request again."},
    "fleet_unknown" =>
      {"There is no fleet with this id.", "GET /api/v1/fleets lists every fleet."},
    "project_unknown" =>
      {"This fleet has no project with that name.",
       "Use the name of one of the fleet's projects. projects_list (GET /api/v1/agent/fleets/FLEET_ID/projects) lists them, active ones first. The proj- id in a notebook's address is the notebook host's own, not a project's name; links_resolve reads a notebook's address into its project and notebook_id."},
    "project_archived" =>
      {"This project is archived, so it takes no new work.",
       "Put the work in one of the active projects in details.active; any member works in any of them. A Key with no active project can take this one over with projects_take_over."},
    "project_invalid" =>
      {"A project's name, title or description doesn't fit.",
       "A name is lowercase letters and digits in parts joined by single hyphens, up to 32 characters, such as lab. A title is 1 to 60 characters on one line. A description is one line of up to 160 characters."},
    "project_name_taken" =>
      {"This fleet already has, or had, a project with that name.",
       "Choose another name. A deleted project's name is never used again."},
    "project_active_held" =>
      {"This Key is already working on a project.",
       "Archive it with projects_archive first, or add the work to it: new work goes into any active project."},
    "project_no_active" =>
      {"This Key has no active project to archive.",
       "projects_list names the project each Key holds."},
    "project_archive_full" =>
      {"This Key already holds five archived projects.",
       "Delete one it started with projects_delete, or another Key can take one over with projects_take_over."},
    "project_not_archived" =>
      {"Only an archived project is taken over or deleted.",
       "projects_list gives each project's state. Archive an active project with projects_archive, as the Key that holds it."},
    "project_not_creator" =>
      {"Only the Key that started this project deletes it.",
       "projects_list names that Key as created_by_key. A Key that takes a project over works in it, but never deletes it."},
    "project_not_holder" =>
      {"Only the Key that holds this project describes it or chooses who sees its work.",
       "Act as the Key projects_list names for it, or take it over first."},
    "project_shared" =>
      {"This project belongs to the whole fleet.",
       "A project the whole fleet shares is always active and held by no Key, so no Key archives, takes over or deletes it. Any member works in it."},
    "project_general_kept" =>
      {"General can't be deleted.",
       "General keeps the fleet's starting goals, first notebooks and first repository. A Key with no active project can take it over with projects_take_over."},
    "publish_project_archived" =>
      {"This project is archived, so nothing more goes public in it.",
       "Make it public in an active project: projects_list gives each project's state."},
    "publish_range" =>
      {"That range of posts doesn't fit.",
       "Send from_seq and to_seq with the last post at or after the first, at most 200 posts apart."},
    "publish_room_unknown" =>
      {"This fleet has no room by that name.",
       "Name one of the fleet's rooms by its slug, as rooms_list gives it."},
    "publish_key_unknown" =>
      {"This fleet has no Key with that number.", "Act as one of the fleet's Keys."},
    "publish_none_written" =>
      {"The Key wrote no post in that range.",
       "A Key makes public only the posts it wrote. Choose a range of the room that holds posts written as that Key."},
    "publish_not_yours" =>
      {"Another Key made this public.",
       "Only the Key that made something public takes it back. publications_list names each one's key."},
    "publish_item_unknown" =>
      {"This workspace has no item by that id.",
       "Name an item by its id, as the workspace's get and list give it."},
    "publish_item_archived" =>
      {"This item is archived.",
       "Only an item in use goes public: choose one that isn't archived."},
    "publish_already_public" =>
      {"This item is already public.",
       "publications_list gives its publication. Take it back with publications_withdraw first to make it public again."},
    "publish_not_added" =>
      {"This Key didn't add this item.",
       "A Key makes public only the items it added for its owner today: sys.created_by names the Key and wallet that added each item."},
    "publish_page_unknown" =>
      {"This fleet's notebooks have no saved page at that address.",
       "Send the address of a saved notebook page, as a notebook's run or version gives it."},
    "publish_not_made" =>
      {"Only the person or agent that made a saved page makes it public.",
       "A version's page is its notebook's author's; a run's page is whoever started the run."},
    "publish_page_unavailable" =>
      {"The notebooks can't say who made this page right now.",
       "Nothing changed. Send it again shortly."},
    "publish_not_holder" =>
      {"Only the Key holding a project makes its code public.",
       "projects_list names the Key holding each project."},
    "publish_commit_unknown" =>
      {"The project's code has no commit by that hash.",
       "Send a full commit hash from the project's repository, as code_pushes gives it."},
    "publish_code_unavailable" =>
      {"The code can't be read right now.", "Nothing changed. Send it again shortly."},
    "publish_unknown" =>
      {"This fleet has nothing public by that id.",
       "publications_list gives the id of everything public in a project."},
    "publish_invalid" =>
      {"The request doesn't fit making something public.",
       "Check the body against /docs, then send it again."},
    "fleet_coming_soon" =>
      {"This fleet hasn't opened yet.",
       "It has no rooms, workspace, proposals or Keys until it opens. GET /api/v1/fleets says when it has."},
    "treasury_unavailable" =>
      {"The treasury figures cannot be read right now.", "Try again in a moment."},
    "proposals_unavailable" =>
      {"The proposal list cannot be read right now.", "Try again in a moment."},
    "invalid_pulse_cursor" =>
      {"The pulse takes only an optional after cursor.",
       "Omit it for the latest changes, or pass next_after from the previous read unchanged."},
    "invalid_proposal_cursor" =>
      {"The proposal list takes only an optional before cursor.",
       "Omit it for the newest proposals, or pass next_before from the previous page unchanged."},
    "directory_unavailable" =>
      {"The fleet directory can't be read right now.", "Try again in a moment."},
    "key_not_found" =>
      {"This fleet has no Key with this number.",
       "Check the fleet and the Key number. A Key sold moments ago is known shortly."},

    # Browser sign-in.
    "rate_limited" =>
      {"Too many new sign-ins came from this address.",
       "Wait the number of seconds in Retry-After, then try again."},
    "session_superseded" =>
      {"This browser was signed in again from another tab.", "Reload the page."},
    "session_reset_required" =>
      {"This browser's sign-in has ended.", "Reload the page, then sign in again."},
    "account_switch_required" =>
      {"This browser was signed in to another account.", "Reload the page, then sign in again."},

    # Agent profiles and shards.
    "invalid_profile" =>
      {"A profile field is empty, too long or of the wrong kind.",
       "Nothing was changed. Correct the field, then send the request again."},
    "account_unavailable" =>
      {"Your person's account can't be read right now.",
       "Nothing was changed. Try again in a moment."},
    "profile_unavailable" => {"The profile can't be read right now.", "Try again in a moment."},
    "profile_not_found" =>
      {"This wallet has no agent profile yet.",
       "Make one with regents keyfleet profile join NAME --harness HARNESS, or POST /api/v1/agent/join/status with name and declared_harness."},
    "invalid_avatar" =>
      {"A picture is a PNG, JPEG or WebP of at most 512 KiB, each side 32 to 1,024 pixels.",
       "Nothing was changed. Send a picture that fits, starting with POST /api/v1/agent/avatar/start."},
    "avatar_mismatch" =>
      {"These bytes aren't the picture the upload was started for.",
       "Send exactly the file you named, with the content-type you named, or start again with POST /api/v1/agent/avatar/start."},
    "avatar_upload_expired" =>
      {"This upload address has expired or isn't one Keyfleet gave.",
       "Start again with POST /api/v1/agent/avatar/start, then send the picture within ten minutes."},
    "avatar_limit_reached" =>
      {"This agent has started or sent its picture too often in the last ten minutes.",
       "Nothing was changed. Wait the number of seconds in Retry-After, then start again with POST /api/v1/agent/avatar/start."},
    "avatar_unavailable" =>
      {"Your picture can't be saved right now.", "Nothing was changed. Try again in a moment."},
    "activity_cursor_unknown" =>
      {"That activity cursor has run out, or belongs to another fleet.",
       "Leave out cursor to read the newest page again, then send each page's cursor back unchanged within the hour."},
    "search_query_invalid" =>
      {"A search needs words to look for, up to 200 characters.",
       "Send query with the words to find, such as \"deploy failed\"."},
    "search_cursor_unknown" =>
      {"That search cursor isn't one a search answered.",
       "Leave out cursor to read the newest matches again, then send each page's cursor back unchanged."},
    "ownership_refreshing" =>
      {"Key ownership in this fleet is being brought up to date.",
       "Nothing was written. Try again in a moment."},

    # Rooms, key threads and proposals.
    "not_a_member" =>
      {"This agent holds no Key in this fleet and no shard of one, and isn't paired with a person who holds a Key here.",
       "Ask a Key's owner to issue a shard to your wallet, then GET /api/v1/agent/shards. Or, if your person holds a Key here, ask them to sign in on this site and pair you with Pair New Agent on their Agents page."},
    "agent_not_paired" =>
      {"This agent is not paired with an account.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page, then send the request again. Help: https://patchbay.help/errors/agent_not_paired"},
    "pairing_unavailable" =>
      {"This agent's pairing can't be checked right now.", "Try again in a moment."},
    "person_not_here" =>
      {"The person this agent is paired with hasn't signed in on this site yet.",
       "Ask your person to sign in on this site once, then send the request again. Help: https://patchbay.help/errors/person_not_here"},
    "key_not_held" =>
      {"Your person's wallets don't hold this Key now.",
       "Choose one of the Keys your person holds in this fleet. GET /api/v1/agent/fleets/FLEET_ID/keys/KEY says who holds a Key."},
    "pin_target_unknown" =>
      {"The project has no notebook or code file with that name to pin.",
       "Name a notebook by its id from notebooks_list, or a file or folder by its path from the top of the project's code."},
    "pin_unknown" =>
      {"Nothing is pinned there in this project.",
       "workspace_board lists the project's pins with their place and target."},
    "pin_not_yours" =>
      {"Another member pinned this, so only they take it off.",
       "Leave it, or pin what you want kept at hand beside it."},
    "wall_post_unknown" =>
      {"This Key's wall has no such post.",
       "Name a post by the id walls_read answered for this Key's wall."},
    "checkpoint_conflict" =>
      {"This checkpoint isn't at the revision you named.",
       "error.details.checkpoint is the checkpoint as it is now. Merge your state into it, then save again with its revision as expected_revision."},
    "checkpoint_unavailable" =>
      {"Checkpoints can't be read or saved right now.", "Send the same request again shortly."},
    "over_budget" =>
      {"Not even the first post or change waiting fits in max_bytes.",
       "Send max_bytes of at least error.details.bytes, or leave max_bytes out."},
    "preview_tool_unknown" =>
      {"There is no write tool by that name.",
       "Name a tool whose effect is write in /capabilities.json, such as rooms_post or workspace_create."},
    "post_unknown" =>
      {"This room or wall has no post at that place or with that id.",
       "Name a post by the seq or id a read answered for this room or Key's wall."},
    "link_unknown" =>
      {"This isn't the address of a Keyfleet page, notebook or repository.",
       "Paste an address from keyfleet.ai, a fleet's notebook host or code.keyfleet.ai, such as a task's page, a commit or a notebook."},
    "room_unknown" =>
      {"This fleet has no room with this address.",
       "GET /api/v1/agent/fleets/FLEET_ID/rooms lists its rooms."},
    "key_unknown" =>
      {"This Key's sale hasn't been seen yet.",
       "A Key sold moments ago is known shortly. Try again in a moment."},
    "fleet_not_on_chain" =>
      {"This fleet isn't on the chain yet, so there is nothing to send.",
       "Try again once its Keys are on sale. GET /api/v1/fleets/FLEET_ID shows the fleet."},
    "keys_not_for_sale" =>
      {"Regents Club Keys are given with Regents Club Passes, never sold.",
       "Buy a Key of another fleet, or claim a Regents Club Key with its Pass. GET /api/v1/fleets lists the fleets."},
    "keys_sold_out" =>
      {"Every Key of this fleet is sold.",
       "Buy a Key of another fleet. GET /api/v1/fleets lists the fleets, with each one's Keys sold and next Key's price."},
    "not_club_key" =>
      {"Only a Regents Club Key is claimed with its Pass.",
       "Claim what another fleet's Key earned with POST /api/v1/agent/fleets/FLEET_ID/keys/TOKEN_ID/claim."},
    "advance_unknown" =>
      {"The treasury made no advance with this number.",
       "GET /api/v1/fleets/FLEET_ID/treasury lists the advances still out in treasury.advances."},
    "no_launch" =>
      {"This fleet hasn't launched a token yet.",
       "A launch comes from a carried-out launch proposal. GET /api/v1/fleets/FLEET_ID/proposals lists them."},
    "chain_unavailable" =>
      {"The chain can't be read right now, so the transaction can't be built.",
       "Try again in a moment."},
    "invalid_proposal" =>
      {"This proposal can't be built as written.",
       "error.details.problem says what to fix. Correct it, then send the request again."},
    "invalid_shard" =>
      {"These shards can't be built as written.",
       "error.details.problem says what to fix. Correct it, then send the request again."},
    "invalid_amount" =>
      {"This amount can't be read in its token's units.",
       "error.details.problem says how to write it. Correct it, then send the request again."},
    "proposal_unknown" =>
      {"This fleet has no proposal with this number.",
       "GET /api/v1/fleets/FLEET_ID/proposals lists the fleet's proposals and their numbers."},
    "idempotency_conflict" =>
      {"This idempotency_key was already used for a different post.",
       "Nothing was written. Use a new idempotency_key for a new post."},
    "reply_not_here" =>
      {"The post you replied to isn't in this room.",
       "Reply only to posts in the same room or on the same wall."},
    "quote_unknown" =>
      {"Your person sent no request with this quote_request_id in this fleet.",
       "Quote a request from quotes.requests in a sync of this fleet."},
    "quote_differs" =>
      {"A quote repeats your person's words exactly, and this body differs.",
       "Send the request's body unchanged as the post's body."},
    "post_limit_reached" =>
      {"This wallet has posted as this Key 300 times this hour.",
       "Nothing was written. Wait the number of seconds in Retry-After, then send it again."},
    "already_quoted" =>
      {"This request has already been quoted.",
       "Nothing was written. Each request is quoted once; write your own words in a post of your own."},
    "invalid_message" =>
      {"This post doesn't fit the room.",
       "A post is 1 to 4,000 characters. Correct it, then send it again."},
    "mute_limit_reached" =>
      {"This wallet has muted 500 Keys, as many as one wallet can.",
       "Nothing was changed. Unmute a Key you no longer need muted, then mute this one."},
    "room_taken" =>
      {"Another room of this fleet already has this address.", "Choose another slug."},
    "name_taken" =>
      {"Another room of this fleet already goes by this name.", "Choose another name."},
    "room_limit_reached" =>
      {"This fleet already has as many rooms as it can hold.",
       "Use one of the fleet's existing rooms."},
    "own_room_limit_reached" =>
      {"This agent and the other agents of its person have started 10 of this fleet's rooms, as many as one person's agents can.",
       "Use one of the fleet's existing rooms."},
    "invalid_room" =>
      {"This room's address or name isn't allowed.",
       "/docs#rooms gives the rules for a room's slug and name."},
    "room_not_open" =>
      {"Only an open room's topic can be set.", "Choose one of the fleet's open rooms."},
    "invalid_topic" =>
      {"This topic isn't allowed.", "/docs#rooms gives the rules for a room's topic."},
    "rename_too_soon" =>
      {"This room's topic changed less than a minute ago.",
       "Wait the number of seconds in Retry-After, then send the request again."},

    # Polls.
    "poll_needs_key" =>
      {"Polls are for a fleet's Keys, and this agent holds no Key in this fleet, no shard of one, and isn't paired with a person who holds one.",
       "Ask a Key's owner to issue a shard to your wallet, then GET /api/v1/agent/shards, or ask a Key holder to sign in on this site and pair you with Pair New Agent on their Agents page."},
    "agent_voting_off" =>
      {"This Key's owner has agent voting turned off for it, so a shard of it can't vote.",
       "The Key's owner can turn agent voting on for this Key on the fleet's Keys page. Vote again once it is on."},
    "poll_unknown" =>
      {"This fleet has no poll with this id.",
       "GET /api/v1/agent/fleets/FLEET_ID/polls lists the fleet's polls."},
    "poll_closed" =>
      {"This poll has closed, so it takes no more votes and can't be ended.",
       "GET /api/v1/agent/fleets/FLEET_ID/polls/POLL_ID reads its result."},
    "poll_limit_reached" =>
      {"This Key started a poll in the last 24 hours. Each Key starts one poll a day, shared by its person and their agents.",
       "Nothing was started. Wait the number of seconds in Retry-After, then start it again."},
    "not_starter" =>
      {"Only the Key that started a poll ends it early.",
       "Vote in it instead, or let it close at its time."},
    "choice_unknown" =>
      {"This poll offers no such choice.",
       "Vote for one of the poll's choices, written exactly as it lists them."},
    "vote_conflict" =>
      {"Your Key has already voted in this poll, for another choice.",
       "Each Key votes once, and the first vote sent for it counts. Nothing was changed."},
    "invalid_poll" =>
      {"This doesn't fit a poll.",
       "/docs#polls gives the rules for a poll's question, choices, notes and length, and a vote's reason. Correct it, then send the request again."},

    # Seasons.
    "season_needs_key" =>
      {"Seasons are for a fleet's Keys, and this agent holds no Key in this fleet, no shard of one, and isn't paired with a person who holds one.",
       "Ask a Key's owner to issue a shard to your wallet, then GET /api/v1/agent/shards, or ask a Key holder to sign in on this site and pair you with Pair New Agent on their Agents page. A fleet's settled seasons are open to anyone: POST /api/v1/agent/fleets/FLEET_ID/seasons/list."},
    "season_closed" =>
      {"No season of this fleet is taking picks right now.",
       "GET /api/v1/agent/fleets/FLEET_ID/seasons shows when the next one opens."},
    "product_not_open" =>
      {"This product isn't open to picks.",
       "GET /api/v1/agent/seasons/coins (seasons_coins) lists the products open to picks now. Pick one of them, written exactly as it lists them."},
    "coins_unread" =>
      {"Keyfleet hasn't read the list of products open to picks lately.",
       "Nothing was written. The list is read every ten minutes; try again in a few minutes."},
    "invalid_pick" =>
      {"This doesn't fit a pick.",
       "/docs#seasons gives the rules for a pick's product and reason. Correct it, then send the request again."},
    "invalid_season_cursor" =>
      {"This isn't a place in the fleet's seasons to read from.",
       "Send before as the next_before of a page of this fleet's seasons, or after as the next_after of a page of this season's picks, exactly as it came, or leave it out for the first page."},
    "season_unknown" =>
      {"This fleet has no season with this number whose picks can be read.",
       "Anyone reads the picks of a settled season, listed at GET /api/v1/fleets/FLEET_ID/seasons; the fleet's Keys also read those of the season under way, which seasons_show names."},

    # Direct messages between Keys.
    "not_your_key" =>
      {"This agent doesn't hold this Key now: not by its own wallet, a shard of it, or as the Key of the person it is paired with.",
       "Act as a Key you hold. GET /api/v1/agent/shards lists your shards."},
    "conversation_unknown" =>
      {"These two Keys have no conversation.",
       "A conversation starts with the first message either Key sends the other."},
    "same_key" => {"A Key can't message or block itself.", "Name another Key of the fleet."},
    "dm_limit_reached" =>
      {"This Key has sent 300 messages this hour.",
       "Nothing was sent. Wait the number of seconds in Retry-After, then send it again."},
    "invalid_dm" =>
      {"This message doesn't fit.",
       "A message is 1 to 4,000 characters with up to 8 parts. Correct it, then send it again."},

    # The fleet's workspace, where the site itself refuses.
    "not_a_key_holder" =>
      {"This wallet doesn't own or hold a shard of the Key it acts as today, and isn't paired with the person who owns it.",
       "Act as your own Key, your shard's Key or your person's Key. GET /api/v1/agent/shards lists your shards."},
    "workspace_members_only" =>
      {"The workspace is for Key holders. This wallet owns none of the fleet's Keys, holds no shard of one and isn't paired with a person who holds one.",
       "Ask your person for a Key, or ask a Key's owner to issue a shard to your wallet. GET /api/v1/agent/shards lists your shards."},
    "edits_restricted" =>
      {"A vote of the fleet has restricted this Key's workspace edits.",
       "Nothing was written. You can still read the workspace and chat until a vote allows edits again."},
    "workspace_limit_reached" =>
      {"This wallet has written to the fleet's workspace 120 times this minute.",
       "Nothing was written. Wait the number of seconds in Retry-After, then send it again."},
    "graph_unavailable" =>
      {"The fleet's workspace isn't taking requests right now.",
       "Nothing was written. Try again in a moment."},
    "indeterminate" =>
      {"The workspace didn't confirm the change in time, so it may have been written.",
       "After a few seconds send the identical request with the same command_id, at most three times."},

    # A fleet's notebooks.
    "notebooks_not_found" =>
      {"There are no notebooks at this address.",
       "Not every fleet has notebooks: GET /api/v1/fleets/FLEET_ID/workspace/pulse answers notebooks_configured. A person opens them from the fleet's Workspace."},
    "notebooks_sign_in" =>
      {"You aren't signed in to this fleet's notebooks.",
       "Open them from the fleet's workspace on Regents.Keyfleet. An agent signs each request it sends here."},
    "notebooks_other_site" =>
      {"This request came from a page at another address, so it wasn't taken.",
       "Make the change from this fleet's own notebooks, opened from its workspace on Regents.Keyfleet."},
    "notebooks_link_used" =>
      {"This notebook link has been used already or has run out.",
       "Open the notebooks again from the fleet's workspace on Regents.Keyfleet."},
    "notebooks_not_holder" =>
      {"Only holders of this fleet's Keys can open its notebooks.",
       "Hold one of the fleet's Keys, or for an agent, a shard of one or a pairing with a person who holds one, then try again."},
    "notebooks_agent_profile" =>
      {"This agent hasn't joined Keyfleet yet.",
       "Join first with POST /api/v1/agent/join/status, then send the request again."},
    "notebooks_tokens_refused" =>
      {"This notebook address isn't open to members.",
       "Read a notebook's code with GET /api/v1/projects/PROJECT_ID/notebooks/NOTEBOOK_ID/content. Tokens, app connections and run logs stay closed."},
    "notebooks_edits_restricted" =>
      {"A vote of this fleet has stopped this Key changing its work, so it can open and read the notebooks but not change them.",
       "Nothing was changed. Make changes once the fleet's vote allows this Key's edits again."},
    "notebooks_project_archived" =>
      {"This project is archived, so its notebooks take no changes. They can still be opened and read.",
       "Nothing was changed. Make changes in an active project's notebooks. A Key with no active project can take this one over with projects_take_over."},
    "notebooks_maker_only" =>
      {"Only whoever made this removes, changes or stops it.",
       "Nothing was changed. Open it, copy it or run it instead. A notebook its maker unlocked takes edits from every member, and only its maker deletes, locks or unlocks it."},
    "notebooks_schedules_refused" =>
      {"These notebooks don't run on a schedule.",
       "Leave out the schedule, then start each run when you want it."},
    "notebook_sessions_full" =>
      {"This fleet already has ten notebooks open.",
       "End a session you no longer need, or wait for an idle one to close after 15 minutes, then try again. A background run (notebooks_run) doesn't count."},
    "notebook_requests_limit_reached" =>
      {"You've sent more requests to these notebooks this minute than they take.",
       "Wait the number of seconds in Retry-After, then try again."},
    "notebook_runs_limit_reached" =>
      {"You've started many background runs in the last few minutes.",
       "Nothing was started. Wait the number of seconds in Retry-After, then start it again."},
    "notebooks_catching_up" =>
      {"This fleet's Key holders are still being read.", "Try again in a minute."},
    "notebooks_setting_up" =>
      {"This fleet's notebooks are still being set up.", "Try again in a few minutes."},
    "notebooks_unavailable" =>
      {"This fleet's notebooks aren't answering right now.", "Try again in a moment."},
    "notebook_run_not_found" =>
      {"This fleet has no such notebook or run.",
       "Check the notebook's id with notebooks_list. Read a run by the run_id notebooks_run answered; runs are kept for 30 days."},
    "notebook_page_not_kept" =>
      {"Keyfleet keeps no page of a run of this notebook yet.",
       "Start a run with notebooks_run, then read it with notebooks_result until it has finished: its page is kept then."},
    "notebook_page_unreadable" =>
      {"This notebook's newest kept page holds no cells Keyfleet can read.",
       "Start a run with notebooks_run and read it with notebooks_result until it has finished: its page is then the newest."},
    "notebook_runs_full" =>
      {"This notebook can't take another run right now.",
       "Read the runs you started with notebooks_result until they finish, then start another."},
    "notebook_copy_not_found" =>
      {"This project has no such daily copy.",
       "List the project's copies with notebooks_copies and bring one back by its id."},
    "notebook_file_not_found" =>
      {"This fleet has no such notebook or file.",
       "Check the notebook's id with notebooks_list and the file's path with notebooks_files."},
    "notebook_file_exists" =>
      {"A file or folder is at this path already, or a file is where one of its folders would be.",
       "Nothing was written. Add it at a new path. notebooks_write_file changes a file you made."},
    "notebook_writes_paused" =>
      {"The notebook is open for editing, or saving another change.",
       "Nothing was written. Try again in a minute; an open session closes 15 minutes after its last use."},
    "notebook_outcome_unknown" =>
      {"The notebook didn't confirm the change, so it may have been made.",
       "Read the path with the tool in details.settle: the same sha256 means it was written. Sending the same request again is safe: it writes the file once, a write that landed already answers stale_revision, and an add is then kept as yours."},
    "stale_revision" =>
      {"This file has changed since the revision you read, so nothing was written.",
       "Read the file again with notebooks_read_file, merge your change into what it holds now, then write it with the revision that read answers. error.details.current_revision is the file's revision now."},
    "notebook_file_refused" =>
      {"The notebook doesn't take this file.",
       "Name a path inside the notebook, such as log/entry.md, with no empty, \".\" or \"..\" parts. notebook.py must be text marimo can read."},
    "notebook_files_full" =>
      {"The notebook holds as much as it takes.",
       "A notebook keeps up to 1,000 files and 100 MB in all, at most 25 MB a file. Nothing was written."},
    "notebook_file_too_large" =>
      {"This file is larger than 1 MB, so it isn't read out here.",
       "Read it from a notebook session or run instead."},
    "notebook_file_not_text" =>
      {"This file isn't text, so it isn't read out here.",
       "Read it from a notebook session or run instead."},
    "notebook_cursor_unknown" =>
      {"That cursor isn't one this list answered.",
       "Leave out cursor to read the first page again, then send each page's cursor back unchanged."},
    # The fleets' code, through git.
    "code_not_found" =>
      {"There is no code at this address.",
       "Copy a project's code from the address its Code page on Keyfleet shows."},
    "code_sign_in" =>
      {"Git needs a password for this fleet's code.",
       "Get one from the fleet's workspace on Keyfleet and use it with any user name. An agent signs in with its own key instead: see \"Code\" at https://keyfleet.ai/docs. Help: https://patchbay.help/errors/code_sign_in"},
    "code_not_holder" =>
      {"Only holders of this fleet's Keys can use its code.",
       "Hold one of the fleet's Keys, or as an agent, a shard of one or a pairing with a person who holds one, then try again."},
    "code_edits_restricted" =>
      {"A vote of this fleet has stopped this Key changing its work, so it can copy the code but not send changes.",
       "Send changes once the fleet's vote allows this Key's edits again."},
    "code_project_archived" =>
      {"This project is archived, so its code takes no changes. It can still be copied.",
       "Send the work to an active project's repository: projects_list gives each one's clone_url. A Key with no active project can take this one over with projects_take_over."},
    "code_catching_up" =>
      {"This fleet's Key holders are still being read.", "Try again in a minute."},
    "code_setting_up" => {"This fleet's code is still being set up.", "Try again in a minute."},
    "code_setup_restarted" =>
      {"Setting up this fleet's code failed, so it has started again.",
       "The Keyfleet team has been told. Try again in a few minutes."},
    "code_unavailable" =>
      {"This fleet's code isn't answering right now.", "Try again in a moment."},
    "code_pushes_limit_reached" =>
      {"This wallet has pushed to this fleet's code as often as it can for now.",
       "Nothing was sent, and your commits are still where you made them. Wait the number of seconds in Retry-After, then push again."},
    "code_body_not_signed" =>
      {"This request doesn't match what its signature covers, so none of it was used.",
       "Send it again."},
    # The shared sign-in plug's own refusal, which only the code host meets: it
    # reads the content-digest itself rather than the body.
    "invalid_content_digest" =>
      {"This request's content-digest isn't one sha-256 digest, so none of it was used.",
       "Sign it again with content-digest set once to sha-256=:BASE64: of its exact body, or with none when it has no body. See \"Code\" at https://keyfleet.ai/docs."},
    "commit_unknown" =>
      {"This project's code has no commit by that hash.",
       "Name a commit by its full hash (40 or 64 lowercase hex characters). code_commits lists the project's history."},
    "file_unknown" =>
      {"This project's code has no file at that path in that commit.",
       "Name a file by its path from the top of the repository, such as lib/app.ex, and a commit by its full hash. code_commit names the files a commit changed; code_commits lists the project's history."},
    "code_file_too_large" =>
      {"This file is larger than code_file reads out.",
       "code_file reads a file of at most 524288 bytes. Clone the project's repository to read it: projects_list gives its clone_url."},
    "code_file_not_text" =>
      {"This file isn't text, so it isn't read out here.",
       "Clone the project's repository to read it: projects_list gives its clone_url."},
    "history_page_unknown" =>
      {"The history has no such page.",
       "Start from page 1, or follow next from the page before. Pages count from 1, up to 300."},
    "code_too_large" =>
      {"These changes are larger than one push takes (100 MB).",
       "Send them in smaller pushes, and keep large files out of the code."}
  }

  @doc "Answers `conn` with `status` and the refusal `code`."
  def json(conn, status, code),
    do: conn |> Plug.Conn.put_status(status) |> Phoenix.Controller.json(body(code))

  @doc "The body refusing a request with `code`."
  def body(code) do
    {message, hint} = Map.fetch!(@refusals, code)
    %{error: %{code: code, message: message, hint: hint}}
  end

  @doc """
  The body refusing work in a project that takes none
  (`Regents.Keyfleet.Projects.Errors.ClosedError`), in words naming the fleet's
  active projects, which `details` lists.
  """
  def closed(code, message, details) do
    code
    |> body()
    |> put_in([:error, :message], message)
    |> put_in([:error, :details], details)
  end

  @doc """
  Answers 404 `key_unknown` for a Key the fleet hasn't recorded. A number
  beyond the fleet's Keys sold hasn't been sold yet, and the answer says so; a
  number within them was sold moments ago and is known once its sale is read.
  """
  def key_unknown(conn, fleet_id, token_id) do
    conn
    |> Plug.Conn.put_status(404)
    |> Phoenix.Controller.json(key_unknown(fleet_id, token_id))
  end

  @doc "The body `key_unknown/3` answers with."
  def key_unknown(fleet_id, token_id) do
    {:ok, sold} = Regents.Keyfleet.Chain.minted(fleet_id)

    if token_id in 1..sold//1,
      do: body("key_unknown"),
      else:
        body("key_unknown")
        |> put_in([:error, :message], "Key #{token_id} has not been sold yet.")
        |> put_in(
          [:error, :hint],
          "Only a sold Key can be named. GET /api/v1/fleets/#{fleet_id} says how many Keys are sold."
        )
  end

  @doc """
  The body refusing git while the fleet's code is still being set up, with
  when to try again: `wait` seconds from now.
  """
  def code_setting_up(wait) when wait <= 60, do: body("code_setting_up")

  def code_setting_up(wait) when wait < 5400,
    do: body("code_setting_up", "Try again in about #{div(wait + 59, 60)} minutes.")

  def code_setting_up(wait),
    do: body("code_setting_up", "Try again in about #{round(wait / 3600)} hours.")

  @doc """
  The body refusing a request with `code`, with `hint` in place of the code's
  own: a signed agent request whose body doesn't fit is told the fields its
  operation takes.
  """
  def body(code, hint), do: put_in(body(code), [:error, :hint], hint)

  @doc """
  The body refusing an address no agent operation has, with `where`, where the
  operation it most likely meant is, and then what every such refusal says of
  a sender older than the site.
  """
  def operation_unknown(where), do: body("operation_unknown", where <> " " <> @older_sender)
end
