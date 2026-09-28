import { BaseError, TransactionReceiptNotFoundError } from "viem";

export const RECEIPT_EXPLORER_BASE = "https://monadscan.com/tx/";

export const RECEIPT_UNKNOWN_TITLE = "Confirmation unknown";
export const RECEIPT_UNKNOWN_BODY =
  "Knot could not read a receipt for this transaction, so the outcome is unknown: it may have confirmed, still be pending, or be missing from the node that answered. Check the explorer before sending anything else.";
export const RECEIPT_UNKNOWN_RETRY_LABEL = "Retry status check";
export const RECEIPT_PENDING_LABEL = "Pending confirmation";
export const RECEIPT_CONFIRMED_LABEL = "Confirmed on Monad";

export type ReceiptPhase = "idle" | "pending" | "confirmed" | "lookup-error";

export type ReceiptQueryState = {
  hash?: string;
  isSuccess: boolean;
  isError: boolean;
};

/**
 * Resolves the action area from the receipt query alone. A lookup failure is a
 * fourth state: the hash is still valid, but confirmation has not been proven
 * either way, so it must never render as a pending or as a revert.
 */
export function receiptPhase({ hash, isSuccess, isError }: ReceiptQueryState): ReceiptPhase {
  if (!hash) return "idle";
  if (isSuccess) return "confirmed";
  if (isError) return "lookup-error";
  return "pending";
}

export function receiptExplorerUrl(hash: string): string {
  return `${RECEIPT_EXPLORER_BASE}${hash}`;
}

export function receiptLookupDetail(error: unknown): string {
  if (error instanceof TransactionReceiptNotFoundError) {
    return "The node answered without a receipt for this hash.";
  }
  const raw =
    error instanceof BaseError
      ? error.shortMessage
      : error instanceof Error
        ? error.message
        : "";
  const cleaned = raw.split("\nVersion:")[0]?.trim() ?? "";
  if (cleaned.length === 0) return "The status read did not return a result.";
  return cleaned.length > 160 ? `${cleaned.slice(0, 157)}…` : cleaned;
}

/**
 * Repeats only the receipt read. It never rebroadcasts the combo and never
 * requests another approval, and it is a no-op once a receipt exists.
 */
export async function retryReceiptLookup(receipt: {
  data: unknown;
  refetch: () => Promise<unknown>;
}): Promise<boolean> {
  if (receipt.data !== undefined) return false;
  await receipt.refetch();
  return true;
}
