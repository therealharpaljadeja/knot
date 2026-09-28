import { describe, expect, it, vi } from "vitest";
import { TransactionReceiptNotFoundError } from "viem";
import {
  RECEIPT_CONFIRMED_LABEL,
  RECEIPT_PENDING_LABEL,
  RECEIPT_UNKNOWN_BODY,
  RECEIPT_UNKNOWN_TITLE,
  receiptExplorerUrl,
  receiptLookupDetail,
  receiptPhase,
  retryReceiptLookup,
} from "./receipt";

const hash = "0x5f0b1c1d8a3b2f4e6c8a0b2d4f6e8a0c2e4a6c8e0a2c4e6a8c0e2a4c6e8a0b2";

describe("receipt phase resolution", () => {
  it("is idle before a transaction hash exists", () => {
    expect(receiptPhase({ hash: undefined, isSuccess: false, isError: false })).toBe("idle");
    expect(receiptPhase({ isSuccess: false, isError: true })).toBe("idle");
  });

  it("is pending while the receipt lookup is still in flight", () => {
    expect(receiptPhase({ hash, isSuccess: false, isError: false })).toBe("pending");
  });

  it("is confirmed once a receipt is available", () => {
    expect(receiptPhase({ hash, isSuccess: true, isError: false })).toBe("confirmed");
  });

  it("is a distinct lookup-error state when the read exhausts its retries", () => {
    const phase = receiptPhase({ hash, isSuccess: false, isError: true });
    expect(phase).toBe("lookup-error");
    expect(phase).not.toBe(RECEIPT_PENDING_LABEL);
  });

  it("prefers a receipt over a latched lookup failure", () => {
    expect(receiptPhase({ hash, isSuccess: true, isError: true })).toBe("confirmed");
  });
});

describe("receipt explorer link", () => {
  it("preserves the transaction hash", () => {
    expect(receiptExplorerUrl(hash)).toBe(`https://monadscan.com/tx/${hash}`);
    expect(receiptExplorerUrl(hash)).toContain(hash);
  });
});

describe("receipt lookup copy", () => {
  it("states an unknown outcome instead of a revert", () => {
    const copy = `${RECEIPT_UNKNOWN_TITLE} ${RECEIPT_UNKNOWN_BODY}`;
    expect(copy).toMatch(/unknown/i);
    expect(copy).not.toMatch(/revert|failed|declined|rejected|cancel+ed/i);
  });

  it("explains a missing receipt as an unread result, not a failed transaction", () => {
    const detail = receiptLookupDetail(
      new TransactionReceiptNotFoundError({ hash: hash as `0x${string}` }),
    );
    expect(detail).toContain("without a receipt");
    expect(detail).not.toMatch(/revert|failed|declined/i);
  });

  it("surfaces a provider message without the viem version footer", () => {
    const error = new Error("HTTP request failed.\n\nVersion: viem@2.55.10");
    expect(receiptLookupDetail(error)).toBe("HTTP request failed.");
  });

  it("falls back when there is no usable message", () => {
    expect(receiptLookupDetail(undefined)).toBe("The status read did not return a result.");
  });

  it("truncates a very long provider message", () => {
    expect(receiptLookupDetail(new Error("x".repeat(400)))).toHaveLength(158);
  });
});

describe("receipt lookup retry", () => {
  it("repeats the read and nothing else", async () => {
    const calls: string[] = [];
    const refetch = vi.fn(async () => {
      calls.push("refetch");
      return { status: "success" };
    });

    const repeated = await retryReceiptLookup({ data: undefined, refetch });

    expect(repeated).toBe(true);
    expect(refetch).toHaveBeenCalledTimes(1);
    expect(calls).toEqual(["refetch"]);
  });

  it("does not re-read once a receipt exists", async () => {
    const refetch = vi.fn(async () => ({ status: "success" }));

    const repeated = await retryReceiptLookup({ data: { status: "success" }, refetch });

    expect(repeated).toBe(false);
    expect(refetch).not.toHaveBeenCalled();
  });

  it("surfaces a failed re-read so the unknown state survives", async () => {
    const refetch = vi.fn(async () => {
      throw new Error("HTTP request failed.");
    });

    await expect(retryReceiptLookup({ data: undefined, refetch })).rejects.toThrow(
      "HTTP request failed.",
    );
  });
});
