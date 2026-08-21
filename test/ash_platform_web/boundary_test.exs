defmodule AshPlatformWeb.BoundaryTest do
  use ExUnit.Case, async: true

  @forbidden ["check_origin: false", "../platform", "/platform/"]

  test "auth has no production database shortcut or old-platform dependency" do
    paths =
      ["mix.exs" | Path.wildcard("{config,lib,test}/**/*.{ex,exs,heex}")]
      |> List.delete(__ENV__.file |> Path.relative_to_cwd())

    for path <- paths,
        forbidden <- @forbidden do
      refute File.read!(path) =~ forbidden, "#{path} contains forbidden boundary #{forbidden}"
    end
  end

  test "the only application migrations are the admitted additive tables" do
    assert [regent_migration] = Path.wildcard("priv/repo/migrations/*_create_regents.exs")

    assert [techtree_migration] =
             Path.wildcard("priv/repo/migrations/*_create_techtree_trees_and_nodes.exs")

    assert [autolaunch_migration] =
             Path.wildcard("priv/repo/migrations/*_create_autolaunch_auctions_and_tokens.exs")

    assert [comments_migration] =
             Path.wildcard("priv/repo/migrations/*_create_record_comments.exs")

    assert [comment_reactions_migration] =
             Path.wildcard("priv/repo/migrations/*_add_techtree_comment_reactions.exs")

    assert [notebook_artifacts_migration] =
             Path.wildcard("priv/repo/migrations/*_add_techtree_notebook_artifacts.exs")

    assert [evidence_state_updates_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_regent_zs65_techtree_evidence_state_updates.exs"
             )

    assert [launch_drafts_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_launch_drafts.exs")

    assert [subjects_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_subjects_and_actions.exs")

    assert [subject_identity_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_add_autolaunch_subject_id_and_token_linkage.exs"
             )

    assert [launch_jobs_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_launch_jobs.exs")

    assert [bids_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_bids.exs")

    assert [bid_prepared_actions_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_bid_prepared_action_fields.exs")

    assert [buyback_prepared_actions_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_add_autolaunch_buyback_prepared_action_fields.exs"
             )

    assert [payment_links_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_payment_links.exs")

    assert [token_auction_identity_migration] =
             Path.wildcard("priv/repo/migrations/*_add_unique_autolaunch_token_auction.exs")

    assert [techtree_graph_migration] =
             Path.wildcard("priv/repo/migrations/*_add_techtree_edges_and_node_layout.exs")

    assert [techtree_public_read_index_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_zs63_techtree_public_read_index.exs")

    assert [techtree_workflow_state_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_zs63_techtree_workflow_state.exs")

    assert [techtree_publication_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_zs64_techtree_publication.exs")

    assert [techtree_fail_safe_state_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_zs64_fail_safe_workflow_state.exs")

    assert [techtree_provenance_payload_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_zs66_techtree_provenance_payload.exs")

    assert [cloud_runtimes_migration] =
             Path.wildcard("priv/repo/migrations/*_add_formation_cloud_runtimes.exs")

    assert [linked_identities_migration] =
             Path.wildcard("priv/repo/migrations/*_add_linked_identities.exs")

    assert [public_profile_migration] =
             Path.wildcard("priv/repo/migrations/*_add_public_regent_profile_projection.exs")

    assert [billing_kernel_migration] =
             Path.wildcard("priv/repo/migrations/*_add_prepaid_authorization_kernel.exs")

    assert [ash_functions_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_install_ash_functions_for_billing_extensions_1.exs"
             )

    assert [agent_pairing_migration] =
             Path.wildcard("priv/repo/migrations/*_agent_pairing.exs")

    assert [session_authorities_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_6eb_12_session_authorities.exs")

    assert [indexer_ledger_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_490_8_1_autolaunch_chain_ledger.exs")

    assert [indexer_canonical_height_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_regent_490_8_1_canonical_height_and_finality.exs"
             )

    assert [indexer_block_frontiers_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_regent_490_8_4_autolaunch_indexer_block_frontiers.exs"
             )

    assert [stake_redeem_operations_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_839_1_1_stake_redeem_operations.exs")

    assert [bid_operations_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_839_5_2_clean_v1_bid_operations.exs")

    assert [clean_v1_launch_drafts_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_490_5_1_clean_v1_launch_drafts.exs")

    assert [subject_wallet_operations_migration] =
             Path.wildcard("priv/repo/migrations/*_regent_490_6_1_clean_v1_subject_wallet.exs")

    assert Enum.sort(Path.wildcard("priv/repo/migrations/*")) ==
             Enum.sort([
               regent_migration,
               techtree_migration,
               autolaunch_migration,
               comments_migration,
               comment_reactions_migration,
               notebook_artifacts_migration,
               evidence_state_updates_migration,
               launch_drafts_migration,
               subjects_migration,
               subject_identity_migration,
               launch_jobs_migration,
               bids_migration,
               bid_prepared_actions_migration,
               buyback_prepared_actions_migration,
               payment_links_migration,
               token_auction_identity_migration,
               techtree_graph_migration,
               techtree_public_read_index_migration,
               techtree_workflow_state_migration,
               techtree_publication_migration,
               techtree_fail_safe_state_migration,
               techtree_provenance_payload_migration,
               cloud_runtimes_migration,
               linked_identities_migration,
               public_profile_migration,
               billing_kernel_migration,
               ash_functions_migration,
               agent_pairing_migration,
               session_authorities_migration,
               indexer_ledger_migration,
               indexer_canonical_height_migration,
               indexer_block_frontiers_migration,
               stake_redeem_operations_migration,
               bid_operations_migration,
               clean_v1_launch_drafts_migration,
               subject_wallet_operations_migration
             ])

    assert_additive_migration(
      regent_migration,
      [
        "create table(:regents",
        "references(:platform_human_users"
      ],
      []
    )

    assert_additive_migration(
      techtree_migration,
      [
        "create table(:trees",
        "create table(:nodes",
        "references(:trees",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_additive_migration(
      autolaunch_migration,
      [
        "create table(:auctions",
        "create table(:tokens",
        "references(:auctions",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      comments_migration,
      [
        "create table(:comments",
        "references(:platform_human_users",
        ~s(prefix: "discussions")
      ],
      ["CREATE SCHEMA IF NOT EXISTS discussions"]
    )

    assert_additive_migration(
      comment_reactions_migration,
      [
        "create table(:comment_reactions",
        "references(:comments",
        "references(:platform_human_users",
        ~s(prefix: "discussions")
      ],
      ["CREATE SCHEMA IF NOT EXISTS discussions"]
    )

    assert_additive_migration(
      notebook_artifacts_migration,
      [
        "create table(:notebook_artifacts",
        "references(:nodes",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_additive_migration(
      evidence_state_updates_migration,
      [
        "create table(:evidence_state_updates",
        "references(:nodes",
        "create index(:evidence_state_updates",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_reversible_migration(
      evidence_state_updates_migration,
      ["drop(table(:evidence_state_updates"]
    )

    assert_additive_migration(
      launch_drafts_migration,
      [
        "create table(:launch_drafts",
        "references(:platform_human_users",
        "references(:regents",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      subjects_migration,
      [
        "create table(:subjects",
        "create table(:subject_actions",
        "references(:subjects",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      subject_identity_migration,
      [
        "alter table(:tokens",
        "alter table(:subjects",
        "add(:subject_id, :text",
        "create unique_index(:subjects, [:subject_id]"
      ],
      []
    )

    assert_additive_migration(
      launch_jobs_migration,
      [
        "create table(:launch_jobs",
        "references(:auctions",
        "create unique_index(:launch_jobs, [:job_id]",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      bids_migration,
      [
        "create table(:bids",
        "references(:auctions",
        "create unique_index(:bids, [:bid_id]",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      bid_prepared_actions_migration,
      [
        "alter table(:bids",
        "add(:auction_address, :text)",
        "add(:onchain_bid_id, :text)",
        "alter table(:auctions",
        "add(:quote_token_address, :text)",
        "add(:quote_token_decimals, :bigint)",
        ~s(prefix: "autolaunch")
      ],
      []
    )

    assert_reversible_migration(
      bid_prepared_actions_migration,
      [
        "remove(:onchain_bid_id)",
        "remove(:auction_address)",
        "remove(:current_clearing_price)",
        "remove(:quote_token_decimals)",
        "remove(:quote_token_address)"
      ]
    )

    assert_additive_migration(
      buyback_prepared_actions_migration,
      [
        "alter table(:tokens",
        "add(:price_quote, :text)",
        "add(:price_source, :text)",
        "add(:price_updated_at, :utc_datetime_usec)",
        "alter table(:subjects",
        "add(:revenue_router_address, :text)",
        ~s(prefix: "autolaunch")
      ],
      []
    )

    assert_reversible_migration(
      buyback_prepared_actions_migration,
      [
        "remove(:revenue_router_address)",
        "remove(:price_updated_at)",
        "remove(:price_source)",
        "remove(:price_quote)"
      ]
    )

    assert_additive_migration(
      payment_links_migration,
      [
        "create table(:payment_links",
        "references(:subjects",
        "create index(:payment_links, [:subject_id]",
        "create unique_index(:payment_links, [:receiver_address]",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      token_auction_identity_migration,
      [
        "create unique_index(:tokens, [:auction_id]",
        ~s(name: "tokens_unique_auction_index"),
        ~s(prefix: "autolaunch")
      ],
      []
    )

    assert_additive_migration(
      techtree_graph_migration,
      [
        "alter table(:nodes",
        "add(:pos_x, :float)",
        "add(:pos_y, :float)",
        ~s|add(:display_kind, :text, null: false, default: "standard")|,
        "create table(:edges",
        "references(:nodes",
        "create unique_index(:edges, [:from_node_id, :to_node_id]",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_reversible_migration(
      techtree_graph_migration,
      [
        "drop(table(:edges",
        "remove(:display_kind)",
        "remove(:pos_y)",
        "remove(:pos_x)"
      ]
    )

    assert_additive_migration(
      techtree_public_read_index_migration,
      [
        "@disable_ddl_transaction true",
        "@disable_migration_lock true",
        ~s|create index(:nodes, [:tree_id, "published_at DESC", "id ASC"]|,
        ~s|name: "nodes_public_tree_page_index"|,
        "concurrently: true",
        ~s|prefix: "techtree"|
      ],
      []
    )

    assert_reversible_migration(
      techtree_public_read_index_migration,
      [~s|drop_if_exists(|, ~s|name: "nodes_public_tree_page_index"|]
    )

    assert_additive_migration(
      techtree_workflow_state_migration,
      [
        "alter table(:nodes",
        ~s|add(:workflow_state, :text, null: false, default: "published")|,
        ~s|prefix: "techtree"|
      ],
      []
    )

    assert_reversible_migration(
      techtree_workflow_state_migration,
      ["remove(:workflow_state)"]
    )

    assert_additive_migration(
      techtree_publication_migration,
      [
        "alter table(:nodes",
        "add(:kind, :text)",
        "add(:manifest_digest, :text)",
        "add(:idempotency_key, :text)",
        "add(:contributor_id, :text)",
        "add(:publisher_agent_id, :text)",
        "add(:publisher_registry_address, :text)",
        "add(:publisher_token_id, :text)",
        "add(:publisher_wallet, :text)",
        "add(:publisher_chain_id, :bigint)",
        "add(:publisher_regent_id, :uuid)",
        "add(:siwa_envelope, :map)",
        "create unique_index(",
        ~s|name: "nodes_unique_publisher_idempotency_index"|,
        ~s|prefix: "techtree"|
      ],
      []
    )

    assert_reversible_migration(
      techtree_publication_migration,
      [
        ~s|name: "nodes_unique_publisher_idempotency_index"|,
        "remove(:siwa_envelope)",
        "remove(:publisher_regent_id)",
        "remove(:publisher_chain_id)",
        "remove(:publisher_wallet)",
        "remove(:publisher_token_id)",
        "remove(:publisher_registry_address)",
        "remove(:publisher_agent_id)",
        "remove(:contributor_id)",
        "remove(:idempotency_key)",
        "remove(:manifest_digest)",
        "remove(:kind)"
      ]
    )

    publication_migration = File.read!(techtree_publication_migration)
    refute publication_migration =~ "workflow_state"
    refute publication_migration =~ "projection"

    assert_additive_migration(
      techtree_fail_safe_state_migration,
      [
        "alter table(:nodes",
        "modify(:workflow_state, :text, default: nil)",
        ~s|prefix: "techtree"|
      ],
      []
    )

    assert_reversible_migration(
      techtree_fail_safe_state_migration,
      ["modify(:workflow_state, :text, default: \"published\")"]
    )

    assert_additive_migration(
      techtree_provenance_payload_migration,
      [
        "alter table(:nodes",
        "add(:manifest_cid, :text)",
        "add(:manifest_hash, :text)",
        "add(:manifest_uri, :text)",
        "add(:lineage, :map)",
        ~s|add(:projection_status, :text, null: false, default: "not_started")|,
        ~s|prefix: "techtree"|
      ],
      []
    )

    assert_reversible_migration(
      techtree_provenance_payload_migration,
      [
        "remove(:projection_status)",
        "remove(:lineage)",
        "remove(:manifest_uri)",
        "remove(:manifest_hash)",
        "remove(:manifest_cid)"
      ]
    )

    assert_additive_migration(
      cloud_runtimes_migration,
      [
        "create table(:cloud_runtimes",
        "references(:platform_human_users",
        "references(:regents"
      ],
      []
    )

    assert_additive_migration(
      linked_identities_migration,
      [
        "create table(:linked_identities",
        "references(:platform_human_users",
        "create unique_index(:linked_identities, [:provider, :human_account_id]",
        "create unique_index(:linked_identities, [:provider, :subject]"
      ],
      []
    )

    assert_additive_migration(
      public_profile_migration,
      [
        "alter table(:regents)",
        "add(:avatar_url, :text)"
      ],
      []
    )

    assert_additive_migration(
      billing_kernel_migration,
      [
        "create table(:billing_accounts,",
        "create table(:billing_ledger_entries,",
        "create table(:billing_spend_reservations,",
        "billing_accounts_authority_balanced"
      ],
      []
    )

    assert_extension_migration(ash_functions_migration)

    assert_additive_migration(
      agent_pairing_migration,
      [
        "create table(:agent_pairing_codes",
        "references(:platform_human_users",
        "references(:regents",
        "create unique_index(:agent_pairing_codes, [:human_account_id]",
        "create unique_index(:agent_pairing_codes, [:code_hash]",
        "create table(:agent_links",
        "create unique_index(:agent_links, [:agent_id]",
        "create unique_index(:agent_links, [:registry_address, :token_id]"
      ],
      []
    )

    assert_reversible_migration(
      agent_pairing_migration,
      ["drop(table(:agent_links))", "drop(table(:agent_pairing_codes))"]
    )

    assert_additive_migration(
      session_authorities_migration,
      [
        "create table(:session_authorities",
        "add(:lineage_digest, :binary, null: false)",
        "add(:generation, :bigint, null: false, default: 0)",
        "add(:revoked_at, :utc_datetime_usec)",
        "references(:platform_human_users",
        "on_delete: :restrict",
        "create unique_index(:session_authorities, [:lineage_digest]",
        "create constraint(:session_authorities, :session_authorities_generation_nonnegative",
        "generation >= 0"
      ],
      []
    )

    assert_reversible_migration(
      session_authorities_migration,
      ["drop(table(:session_authorities))"]
    )

    session_authorities = File.read!(session_authorities_migration)
    refute session_authorities =~ "execute"
    # The raw lineage is never a column; only its digest is stored.
    refute session_authorities =~ "add(:lineage,"

    assert_additive_migration(
      indexer_ledger_migration,
      [
        "create table(:indexer_sources",
        "create table(:indexer_logs",
        "create table(:indexer_cursors",
        "create table(:indexer_blocks",
        "references(:indexer_blocks",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    # One canonical block per height, and finality only ever on a canonical
    # block, are database facts rather than conventions the writer keeps.
    assert_additive_migration(
      indexer_canonical_height_migration,
      [
        ~s(name: "indexer_blocks_canonical_height_index"),
        "unique: true",
        ~s(where: "canonical"),
        ":indexer_blocks_finalized_is_canonical",
        "canonical or not finalized"
      ],
      []
    )

    assert_reversible_migration(indexer_canonical_height_migration, [
      ":indexer_blocks_finalized_is_canonical",
      ~s(name: "indexer_blocks_canonical_height_index")
    ])

    # The finalized frontier gets an ordinary index and nothing else: promotion
    # and retirement rewrite `finalized` and `canonical`, so a partial predicate
    # on either would move rows out of the index the frontier read depends on.
    assert_additive_migration(
      indexer_block_frontiers_migration,
      [
        ~s(name: "indexer_blocks_finalized_frontier_index"),
        "[:chain_id, :finalized, :block_number]"
      ],
      []
    )

    refute File.read!(indexer_block_frontiers_migration) =~ "where:"

    assert_reversible_migration(indexer_block_frontiers_migration, [
      ~s(name: "indexer_blocks_finalized_frontier_index")
    ])

    # One active Stake or Redeem operation per account and capability, one
    # immutable action identity, and one owner per submitted hash are database
    # facts rather than conventions a socket keeps.
    assert_additive_migration(
      stake_redeem_operations_migration,
      [
        "create table(:stake_redeem_operations",
        "add(:action_id, :text, null: false)",
        "add(:capability, :text, null: false)",
        "add(:envelope, :map, null: false)",
        ~s|add(:state, :text, null: false, default: "prepared")|,
        "add(:approval_transaction_hash, :text)",
        "add(:action_transaction_hash, :text)",
        "add(:terminal_at, :utc_datetime_usec)",
        "references(:platform_human_users",
        "on_delete: :restrict",
        ~s(name: "stake_redeem_operations_unique_action_id_index"),
        ~s(name: "stake_redeem_operations_unique_approval_transaction_hash_index"),
        ~s(name: "stake_redeem_operations_unique_action_transaction_hash_index"),
        ~s(name: "stake_redeem_operations_one_active_per_capability_index"),
        ~s|where: "(terminal_at IS NULL)"|
      ],
      []
    )

    assert_reversible_migration(
      stake_redeem_operations_migration,
      ["drop(table(:stake_redeem_operations))"]
    )

    # No raw session lineage is ever a column on an operation.
    refute File.read!(stake_redeem_operations_migration) =~ "lineage"

    # One open bid per account, one immutable reviewed identity, and one owner
    # per bound hash are database facts rather than conventions a socket keeps.
    assert_additive_migration(
      bid_operations_migration,
      [
        "create table(:bid_operations",
        "add(:action_id, :text, null: false)",
        "add(:envelope, :map, null: false)",
        "add(:signer, :text, null: false)",
        "add(:step, :text, null: false)",
        ~s|add(:state, :text, null: false, default: "prepared")|,
        "add(:token_approval_transaction_hash, :text)",
        "add(:permit2_approval_transaction_hash, :text)",
        "add(:bid_transaction_hash, :text)",
        "add(:onchain_bid_id, :text)",
        "add(:terminal_at, :utc_datetime_usec)",
        "references(:platform_human_users",
        "on_delete: :restrict",
        ~s(name: "bid_operations_unique_action_id_index"),
        ~s(name: "bid_operations_unique_token_approval_transaction_hash_index"),
        ~s(name: "bid_operations_unique_permit2_approval_transaction_hash_index"),
        ~s(name: "bid_operations_unique_bid_transaction_hash_index"),
        ~s(name: "bid_operations_one_open_per_account_index"),
        ~s|where: "(terminal_at IS NULL)"|,
        ~s|prefix: "autolaunch"|
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_reversible_migration(
      bid_operations_migration,
      [~s|drop(table(:bid_operations, prefix: "autolaunch"))|]
    )

    # No raw session lineage is ever a column on a bid operation either.
    refute File.read!(bid_operations_migration) =~ "lineage"

    # Clean V1 only widens the launch draft: it adds the new columns and lets the
    # superseded title go null.
    assert_additive_migration(
      clean_v1_launch_drafts_migration,
      [
        "alter table(:launch_drafts",
        "modify(:title, :text, null: true)",
        "add(:website, :text)",
        "add(:image, :text)",
        "add(:treasury, :text)",
        "add(:recovery_admin, :text)",
        "add(:required_regent_raised, :text)",
        ~s|prefix: "autolaunch"|
      ],
      []
    )

    # Rolling back restores the old NOT NULL title, so it must first give every
    # clean-V1 row the name it already holds instead of failing or deleting it.
    assert_reversible_migration(
      clean_v1_launch_drafts_migration,
      [
        ~s|UPDATE "autolaunch"."launch_drafts" SET "title" = "token_name" WHERE "title" IS NULL|,
        "remove(:required_regent_raised)",
        "modify(:title, :text, null: false)"
      ]
    )

    # `name` and `description` are renames in Elixir alone, so no row is rewritten
    # and no superseded column is taken away.
    [clean_v1_launch_drafts_up, clean_v1_launch_drafts_down] =
      clean_v1_launch_drafts_migration
      |> File.read!()
      |> String.split("  def down do", parts: 2)

    refute clean_v1_launch_drafts_down =~ "DELETE"
    refute clean_v1_launch_drafts_down =~ "drop("

    refute clean_v1_launch_drafts_up =~ "remove("
    refute clean_v1_launch_drafts_up =~ "rename"
    refute clean_v1_launch_drafts_up =~ "token_name"
    refute clean_v1_launch_drafts_up =~ "summary"

    # The clean-V1 subject wallet lane only adds: one nullable projection column
    # on subjects, and the durable operation table with the identities that
    # decide its races.
    assert_additive_migration(
      subject_wallet_operations_migration,
      [
        "alter table(:subjects",
        "add(:canonical_receiver_address, :text)",
        "create table(:subject_wallet_operations",
        "add(:action_id, :text, null: false)",
        "add(:subject_id, :text, null: false)",
        "add(:kind, :text, null: false)",
        "add(:envelope, :map, null: false)",
        "add(:signer, :text, null: false)",
        "add(:step, :text, null: false)",
        ~s|add(:state, :text, null: false, default: "prepared")|,
        "add(:approval_transaction_hash, :text)",
        "add(:action_transaction_hash, :text)",
        "add(:terminal_at, :utc_datetime_usec)",
        "references(:platform_human_users",
        "on_delete: :restrict",
        ~s(name: "subject_wallet_operations_unique_action_id_index"),
        ~s(name: "subject_wallet_operations_unique_approval_hash_index"),
        ~s(name: "subject_wallet_operations_unique_action_hash_index"),
        ~s(name: "subject_wallet_operations_one_open_per_subject_index"),
        ~s|where: "(terminal_at IS NULL)"|,
        ~s|prefix: "autolaunch"|
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    # Rolling back takes away only what this migration added, and never a
    # superseded Subject projection column that 490.8.2/.3 still owns.
    assert_reversible_migration(
      subject_wallet_operations_migration,
      [
        ~s|drop(table(:subject_wallet_operations, prefix: "autolaunch"))|,
        "remove(:canonical_receiver_address)"
      ]
    )

    subject_wallet_down =
      subject_wallet_operations_migration
      |> File.read!()
      |> String.split("  def down do", parts: 2)
      |> List.last()

    for retained <- [
          "ingress_address",
          "splitter_address",
          "treasury_address",
          "payment_links",
          "bid_operations"
        ] do
      refute subject_wallet_down =~ retained
    end

    # No raw session lineage is ever a column on a subject wallet operation.
    refute File.read!(subject_wallet_operations_migration) =~ "lineage"
  end

  defp assert_additive_migration(path, required_fragments, allowed_statements) do
    source = File.read!(path)
    [up, _down] = String.split(source, "  def down do", parts: 2)

    for fragment <- required_fragments, do: assert(up =~ fragment)
    refute up =~ "drop("

    statements =
      ~r/execute\("([^"]+)"\)/
      |> Regex.scan(up, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    assert statements == allowed_statements
  end

  defp assert_reversible_migration(path, required_fragments) do
    source = File.read!(path)
    [_up, down] = String.split(source, "  def down do", parts: 2)

    for fragment <- required_fragments, do: assert(down =~ fragment)
  end

  defp assert_extension_migration(path) do
    source = File.read!(path)
    [up, _down] = String.split(source, "  def down do", parts: 2)

    for function <- [
          "ash_elixir_or",
          "ash_elixir_and",
          "ash_trim_whitespace",
          "ash_raise_error",
          "ash_required",
          "uuid_generate_v7"
        ],
        do: assert(up =~ "CREATE OR REPLACE FUNCTION #{function}")

    refute up =~ "DROP FUNCTION"
    refute up =~ "create table("
    refute up =~ "alter table("
  end

  test "only the admitted canonical domains are configured" do
    assert Application.fetch_env!(:ash_platform, :ash_domains) == [
             AshPlatform.Accounts,
             AshPlatform.Billing,
             AshPlatform.Discussions,
             AshPlatform.Formation,
             AshPlatform.Techtree,
             AshPlatform.Autolaunch,
             AshPlatform.Redemption,
             AshPlatform.Staking
           ]
  end

  test "production database startup is enabled only after canonical configuration succeeds" do
    runtime = File.read!("config/runtime.exs")
    assert runtime =~ "config :ash_platform, :database_startup_enabled, true"
    assert runtime =~ "AshPlatform.DatabaseConfig.runtime_config!(config_env())"
    assert runtime =~ "AshPlatform.DatabaseConfig.release_config!()"
    assert runtime =~ ~s|System.get_env("ASH_PLATFORM_RELEASE_COMMAND") == "migrate"|
  end

  test "runtime code never reads the generic database URL" do
    legacy_lookup = ~s|System.get_env("DATABASE_URL")|

    for path <- Path.wildcard("{config,lib,rel}/**/*"), File.regular?(path) do
      refute File.read!(path) =~ legacy_lookup, "#{path} reads the generic database URL"
    end
  end

  test "development keeps origin protection on an exact loopback allowlist" do
    endpoint_config =
      "config/dev.exs"
      |> Config.Reader.read!(env: :dev)
      |> Keyword.fetch!(:ash_platform)
      |> Keyword.fetch!(AshPlatformWeb.Endpoint)

    assert Keyword.fetch!(endpoint_config, :check_origin) == [
             "http://localhost:4000",
             "http://127.0.0.1:4000"
           ]
  end

  test "test keeps origin protection on its exact loopback allowlist" do
    endpoint_config =
      "config/test.exs"
      |> Config.Reader.read!(env: :test)
      |> Keyword.fetch!(:ash_platform)
      |> Keyword.fetch!(AshPlatformWeb.Endpoint)

    assert Keyword.fetch!(endpoint_config, :check_origin) == ["http://127.0.0.1:4002"]
  end
end
