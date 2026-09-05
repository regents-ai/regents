import type {
  X402FetchParams,
  X402PrepareParams,
  X402QuoteParams,
  X402ReceiptGetParams,
  X402RefundParams,
  X402RequestInput,
} from "../../internal-types/index.js";
import type { RuntimeContext } from "../runtime.js";
import { RegentX402Client } from "../x402/client.js";

const clientForContext = (ctx: RuntimeContext): RegentX402Client =>
  new RegentX402Client({
    stateDir: ctx.config.runtime.stateDir,
    signer: ctx.signer,
  });

export const handleX402Details = (ctx: RuntimeContext, params: X402RequestInput) =>
  clientForContext(ctx).details(params);

export const handleX402Quote = (ctx: RuntimeContext, params: X402QuoteParams) =>
  clientForContext(ctx).quote(params);

export const handleX402Prepare = (ctx: RuntimeContext, params: X402PrepareParams) =>
  clientForContext(ctx).prepare(params);

export const handleX402Fetch = (ctx: RuntimeContext, params: X402FetchParams) =>
  clientForContext(ctx).fetchApproved(params);

export const handleX402Refund = (ctx: RuntimeContext, params: X402RefundParams) =>
  clientForContext(ctx).refund(params);

export const handleX402ReceiptGet = (ctx: RuntimeContext, params: X402ReceiptGetParams) =>
  clientForContext(ctx).receiptGet(params);
