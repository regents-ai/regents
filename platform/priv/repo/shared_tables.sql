-- Tables this repository reads but does not own, in the shape the local test
-- suite and the staging bootstrap run on. Production has the real tables:
-- regent_names.platform_human_users is owned by the platform and the
-- autolaunch_app tables by Autolaunch. Nothing here runs against production.
-- Every statement is idempotent, so the fixture can load this file on every run.
CREATE SCHEMA IF NOT EXISTS regent_names;
CREATE TABLE IF NOT EXISTS regent_names.platform_human_users (
    id bigserial PRIMARY KEY,
    privy_user_id varchar(255) NOT NULL UNIQUE,
    wallet_address varchar(255),
    wallet_addresses varchar(255)[] NOT NULL DEFAULT '{}',
    world_human_id varchar(255) UNIQUE,
    world_verified_at timestamp(0) without time zone,
    display_name varchar(80),
    avatar jsonb,
    created_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);
CREATE SCHEMA IF NOT EXISTS autolaunch_app;
CREATE TABLE IF NOT EXISTS autolaunch_app.treasury_security_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    address text NOT NULL,
    chain_id bigint NOT NULL,
    classification text NOT NULL,
    safe_version text,
    safe_singleton text,
    owner_addresses text[] DEFAULT ARRAY[]::text[] NOT NULL,
    owner_count bigint DEFAULT 0 NOT NULL,
    threshold bigint,
    modules text[] DEFAULT ARRAY[]::text[] NOT NULL,
    guard text,
    fallback_handler text,
    configuration_fingerprint text NOT NULL,
    source_block_number bigint NOT NULL,
    source_block_hash text NOT NULL,
    observed_at timestamp without time zone NOT NULL,
    verification_state text NOT NULL,
    verification_reason text NOT NULL,
    usdc_evidence jsonb,
    regent_evidence jsonb,
    outbound_evidence jsonb,
    downgrade_state text DEFAULT 'none'::text NOT NULL,
    prior_verified_fingerprint text,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL
);
CREATE TABLE IF NOT EXISTS autolaunch_app.auctions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    summary text,
    featured boolean DEFAULT false NOT NULL,
    state text DEFAULT 'created'::text NOT NULL,
    opened_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    auction_address text,
    quote_token_address text,
    quote_token_symbol text,
    quote_token_decimals bigint,
    current_clearing_price text,
    treasury_address text,
    treasury_security_report_id uuid CONSTRAINT auctions_treasury_security_report_id_fkey REFERENCES autolaunch_app.treasury_security_reports(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.bids (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bid_id text NOT NULL,
    owner_address text NOT NULL,
    amount text NOT NULL,
    max_price text,
    current_clearing_price text,
    estimated_tokens_if_end_now text,
    status text DEFAULT 'active'::text NOT NULL,
    exited_at timestamp without time zone,
    claimed_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    auction_id uuid NOT NULL CONSTRAINT bids_auction_id_fkey REFERENCES autolaunch_app.auctions(id),
    auction_address text,
    onchain_bid_id text
);
CREATE TABLE IF NOT EXISTS autolaunch_app.tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    symbol text NOT NULL,
    summary text,
    graduated_at timestamp without time zone NOT NULL,
    top_rank bigint,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    auction_id uuid NOT NULL CONSTRAINT tokens_auction_id_fkey REFERENCES autolaunch_app.auctions(id),
    subject_id text,
    price_quote text,
    price_source text,
    price_updated_at timestamp without time zone,
    treasury_address text,
    treasury_security_report_id uuid CONSTRAINT tokens_treasury_security_report_id_fkey REFERENCES autolaunch_app.treasury_security_reports(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.launch_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id text NOT NULL,
    status text NOT NULL,
    step text NOT NULL,
    agent_id text NOT NULL,
    agent_name text,
    token_name text NOT NULL,
    token_symbol text NOT NULL,
    chain_id bigint NOT NULL,
    agent_safe_address text,
    auction_address text,
    token_address text,
    hook_address text,
    revenue_share_splitter_address text,
    started_at timestamp without time zone,
    finished_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    auction_id uuid CONSTRAINT launch_jobs_auction_id_fkey REFERENCES autolaunch_app.auctions(id),
    treasury_address text,
    treasury_security_report_id uuid CONSTRAINT launch_jobs_treasury_security_report_id_fkey REFERENCES autolaunch_app.treasury_security_reports(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.subjects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_kind text NOT NULL,
    chain_id bigint NOT NULL,
    token_address text,
    splitter_address text,
    ingress_address text,
    treasury_address text,
    factory_address text,
    creator_address text,
    staker_pool_bps bigint,
    protocol_skim_bps_snapshot bigint,
    current_protocol_skim_bps bigint,
    protocol_fee_usdc_total_raw text,
    regent_emission_total_raw text,
    pending_buyback_usdc_raw text,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    subject_id text NOT NULL,
    revenue_router_address text,
    canonical_receiver_address text,
    treasury_security_report_id uuid CONSTRAINT subjects_treasury_security_report_id_fkey REFERENCES autolaunch_app.treasury_security_reports(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.payment_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    receiver_address text NOT NULL,
    label text NOT NULL,
    created_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    subject_id uuid NOT NULL CONSTRAINT payment_links_subject_id_fkey REFERENCES autolaunch_app.subjects(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.subject_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    action text NOT NULL,
    owner_address text,
    chain_id bigint NOT NULL,
    tx_hash text,
    amount text,
    status text DEFAULT 'pending'::text NOT NULL,
    block_number bigint,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    subject_id uuid NOT NULL CONSTRAINT subject_actions_subject_id_fkey REFERENCES autolaunch_app.subjects(id)
);
CREATE TABLE IF NOT EXISTS autolaunch_app.indexer_blocks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id bigint NOT NULL,
    block_number bigint NOT NULL,
    block_hash text NOT NULL,
    parent_hash text NOT NULL,
    canonical boolean DEFAULT true NOT NULL,
    finalized boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    CONSTRAINT indexer_blocks_block_number_nonnegative CHECK ((block_number >= 0)),
    CONSTRAINT indexer_blocks_finalized_is_canonical CHECK ((canonical OR (NOT finalized)))
);
CREATE TABLE IF NOT EXISTS autolaunch_app.indexer_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id bigint NOT NULL,
    block_hash text NOT NULL,
    log_index bigint NOT NULL,
    transaction_hash text NOT NULL,
    transaction_index bigint NOT NULL,
    address text NOT NULL,
    topics text[] NOT NULL,
    data text NOT NULL,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    block_id uuid NOT NULL CONSTRAINT indexer_logs_block_id_fkey REFERENCES autolaunch_app.indexer_blocks(id) ON DELETE RESTRICT,
    CONSTRAINT indexer_logs_log_index_nonnegative CHECK ((log_index >= 0)),
    CONSTRAINT indexer_logs_transaction_index_nonnegative CHECK ((transaction_index >= 0))
);
CREATE TABLE IF NOT EXISTS autolaunch_app.indexer_cursors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id bigint NOT NULL,
    next_block_to_fetch bigint NOT NULL,
    lease_owner text,
    lease_expires_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    CONSTRAINT indexer_cursors_next_block_nonnegative CHECK ((next_block_to_fetch >= 0))
);
CREATE TABLE IF NOT EXISTS autolaunch_app.indexer_sources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id bigint NOT NULL,
    address text NOT NULL,
    start_block bigint NOT NULL,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    CONSTRAINT indexer_sources_start_block_nonnegative CHECK ((start_block >= 0))
);
CREATE TABLE IF NOT EXISTS autolaunch_app.launch_drafts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text,
    token_name text NOT NULL,
    symbol text NOT NULL,
    summary text,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    human_account_id bigint NOT NULL CONSTRAINT launch_drafts_human_account_id_fkey REFERENCES regent_names.platform_human_users(id),
    regent_id uuid NOT NULL,
    website text,
    image text,
    treasury text,
    required_regent_raised text,
    treasury_path text DEFAULT 'safe'::text NOT NULL
);
CREATE TABLE IF NOT EXISTS autolaunch_app.launch_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    action_id text NOT NULL,
    envelope jsonb NOT NULL,
    signer text NOT NULL,
    step text NOT NULL,
    state text DEFAULT 'prepared'::text NOT NULL,
    approval_transaction_hash text,
    launch_transaction_hash text,
    result jsonb DEFAULT '{}'::jsonb,
    reason text,
    terminal_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    human_account_id bigint NOT NULL CONSTRAINT launch_operations_human_account_id_fkey REFERENCES regent_names.platform_human_users(id) ON DELETE RESTRICT,
    launch_draft_id uuid NOT NULL CONSTRAINT launch_operations_launch_draft_id_fkey REFERENCES autolaunch_app.launch_drafts(id) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS autolaunch_app.bid_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    action_id text NOT NULL,
    envelope jsonb NOT NULL,
    signer text NOT NULL,
    step text NOT NULL,
    state text DEFAULT 'prepared'::text NOT NULL,
    token_approval_transaction_hash text,
    permit2_approval_transaction_hash text,
    bid_transaction_hash text,
    onchain_bid_id text,
    reason text,
    terminal_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    human_account_id bigint NOT NULL CONSTRAINT bid_operations_human_account_id_fkey REFERENCES regent_names.platform_human_users(id) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS autolaunch_app.subject_wallet_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    action_id text NOT NULL,
    subject_id text NOT NULL,
    kind text NOT NULL,
    envelope jsonb NOT NULL,
    signer text NOT NULL,
    step text NOT NULL,
    state text DEFAULT 'prepared'::text NOT NULL,
    approval_transaction_hash text,
    action_transaction_hash text,
    result jsonb DEFAULT '{}'::jsonb,
    reason text,
    terminal_at timestamp without time zone,
    inserted_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    updated_at timestamp without time zone DEFAULT (now() AT TIME ZONE 'utc'::text) NOT NULL,
    human_account_id bigint NOT NULL CONSTRAINT subject_wallet_operations_human_account_id_fkey REFERENCES regent_names.platform_human_users(id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX IF NOT EXISTS bid_operations_one_open_per_account_index ON autolaunch_app.bid_operations USING btree (human_account_id) WHERE (terminal_at IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS bid_operations_unique_action_id_index ON autolaunch_app.bid_operations USING btree (action_id);
CREATE UNIQUE INDEX IF NOT EXISTS bid_operations_unique_bid_transaction_hash_index ON autolaunch_app.bid_operations USING btree (bid_transaction_hash);
CREATE UNIQUE INDEX IF NOT EXISTS bid_operations_unique_permit2_approval_transaction_hash_index ON autolaunch_app.bid_operations USING btree (permit2_approval_transaction_hash);
CREATE UNIQUE INDEX IF NOT EXISTS bid_operations_unique_token_approval_transaction_hash_index ON autolaunch_app.bid_operations USING btree (token_approval_transaction_hash);
CREATE INDEX IF NOT EXISTS bids_auction_id_index ON autolaunch_app.bids USING btree (auction_id);
CREATE INDEX IF NOT EXISTS bids_owner_address_index ON autolaunch_app.bids USING btree (owner_address);
CREATE INDEX IF NOT EXISTS bids_status_index ON autolaunch_app.bids USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS bids_unique_bid_id_index ON autolaunch_app.bids USING btree (bid_id);
CREATE UNIQUE INDEX IF NOT EXISTS indexer_blocks_canonical_height_index ON autolaunch_app.indexer_blocks USING btree (chain_id, block_number) WHERE canonical;
CREATE INDEX IF NOT EXISTS indexer_blocks_finalized_frontier_index ON autolaunch_app.indexer_blocks USING btree (chain_id, finalized, block_number);
CREATE UNIQUE INDEX IF NOT EXISTS indexer_blocks_unique_block_index ON autolaunch_app.indexer_blocks USING btree (chain_id, block_hash);
CREATE UNIQUE INDEX IF NOT EXISTS indexer_cursors_unique_chain_index ON autolaunch_app.indexer_cursors USING btree (chain_id);
CREATE UNIQUE INDEX IF NOT EXISTS indexer_logs_unique_log_index ON autolaunch_app.indexer_logs USING btree (chain_id, block_hash, log_index);
CREATE UNIQUE INDEX IF NOT EXISTS indexer_sources_unique_source_index ON autolaunch_app.indexer_sources USING btree (chain_id, address);
CREATE INDEX IF NOT EXISTS launch_drafts_human_account_id_index ON autolaunch_app.launch_drafts USING btree (human_account_id);
CREATE INDEX IF NOT EXISTS launch_drafts_regent_id_index ON autolaunch_app.launch_drafts USING btree (regent_id);
CREATE UNIQUE INDEX IF NOT EXISTS launch_jobs_unique_job_id_index ON autolaunch_app.launch_jobs USING btree (job_id);
CREATE UNIQUE INDEX IF NOT EXISTS launch_operations_one_open_per_account_index ON autolaunch_app.launch_operations USING btree (human_account_id) WHERE (terminal_at IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS launch_operations_unique_launch_action_id_index ON autolaunch_app.launch_operations USING btree (action_id);
CREATE UNIQUE INDEX IF NOT EXISTS launch_operations_unique_launch_approval_hash_index ON autolaunch_app.launch_operations USING btree (approval_transaction_hash);
CREATE UNIQUE INDEX IF NOT EXISTS launch_operations_unique_launch_hash_index ON autolaunch_app.launch_operations USING btree (launch_transaction_hash);
CREATE INDEX IF NOT EXISTS payment_links_subject_id_index ON autolaunch_app.payment_links USING btree (subject_id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_links_unique_receiver_address_index ON autolaunch_app.payment_links USING btree (receiver_address);
CREATE UNIQUE INDEX IF NOT EXISTS subject_wallet_operations_one_open_per_subject_index ON autolaunch_app.subject_wallet_operations USING btree (human_account_id, subject_id) WHERE (terminal_at IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS subject_wallet_operations_unique_action_hash_index ON autolaunch_app.subject_wallet_operations USING btree (action_transaction_hash);
CREATE UNIQUE INDEX IF NOT EXISTS subject_wallet_operations_unique_action_id_index ON autolaunch_app.subject_wallet_operations USING btree (action_id);
CREATE UNIQUE INDEX IF NOT EXISTS subject_wallet_operations_unique_approval_hash_index ON autolaunch_app.subject_wallet_operations USING btree (approval_transaction_hash);
CREATE UNIQUE INDEX IF NOT EXISTS subjects_unique_subject_id_index ON autolaunch_app.subjects USING btree (subject_id);
CREATE UNIQUE INDEX IF NOT EXISTS tokens_unique_auction_index ON autolaunch_app.tokens USING btree (auction_id);
CREATE INDEX IF NOT EXISTS treasury_security_reports_address_source_block_number_index ON autolaunch_app.treasury_security_reports USING btree (address, source_block_number);
