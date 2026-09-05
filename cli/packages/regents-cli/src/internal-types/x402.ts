export type X402HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface X402RequestInput {
  url: string;
  method?: X402HttpMethod;
  headers?: Record<string, string>;
  body?: string;
}

export interface X402QuoteParams extends X402RequestInput {
  max_amount?: string;
  max_deposit_amount?: string;
}

export interface X402PrepareParams extends X402QuoteParams {
  approve?: boolean;
}

export interface X402FetchParams extends X402RequestInput {
  intent_id: string;
}

export interface X402ReceiptGetParams {
  id: string;
}

export interface X402RefundParams {
  url: string;
  headers?: Record<string, string>;
  amount?: string;
}

export interface X402SelectedPaymentRequirement {
  scheme: string;
  network: string;
  asset: string;
  amount: string;
  pay_to: string;
  max_timeout_seconds: number;
  extra: Record<string, unknown>;
  requirement_hash: string;
}

export interface PaymentBindingV1 {
  version: "PaymentBindingV1";
  resource_id: string;
  buyer_agent_id: string | null;
  seller_agent_id: string | null;
  network: string;
  asset: string;
  amount_atomic: string;
  pay_to: string;
  expires_at: string | null;
  nonce: string;
  binding_hash: string;
}

export interface X402RequestFingerprint {
  url: string;
  method: X402HttpMethod;
  body_sha256: string | null;
  headers_sha256: string;
  request_hash: string;
}

export interface X402DetailsResponse {
  ok: true;
  payment_required: boolean;
  status: number;
  request: X402RequestFingerprint;
  x402_version?: number;
  resource?: Record<string, unknown>;
  accepts?: X402SelectedPaymentRequirement[];
  payment_required_hash?: string;
  error?: string;
}

export interface X402QuoteResponse {
  ok: true;
  payment_required: true;
  request: X402RequestFingerprint;
  x402_version: number;
  resource: Record<string, unknown>;
  selected: X402SelectedPaymentRequirement;
  payment_required_hash: string;
  quoted_at: string;
}

export interface X402IntentRecord {
  intent_id: string;
  approval_status: "pending" | "approved" | "used";
  request: X402RequestFingerprint;
  x402_version: number;
  resource: Record<string, unknown>;
  selected: X402SelectedPaymentRequirement;
  payment_binding: PaymentBindingV1;
  payment_required_hash: string;
  max_amount?: string;
  max_deposit_amount?: string;
  created_at: string;
  expires_at: string;
  approved_at?: string;
  used_at?: string;
  receipt_id?: string;
}

export interface X402PrepareResponse {
  ok: true;
  intent: X402IntentRecord;
  next_action:
    | {
        kind: "approve_locally";
        command: string;
      }
    | {
        kind: "fetch";
        command: string;
      };
}

export interface X402ReceiptRecord {
  receipt_id: string;
  intent_id: string;
  url: string;
  method: X402HttpMethod;
  status: number;
  ok: boolean;
  payment_required_hash: string;
  requirement_hash: string;
  settlement: Record<string, unknown> | null;
  created_at: string;
}

export interface X402FetchResponse {
  ok: boolean;
  status: number;
  content_type: string | null;
  body_text: string;
  receipt: X402ReceiptRecord | null;
}

export interface X402ReceiptGetResponse {
  ok: true;
  receipt: X402ReceiptRecord | null;
}

export interface X402RefundResponse {
  ok: true;
  url: string;
  amount: string | null;
  settlement: Record<string, unknown>;
}
