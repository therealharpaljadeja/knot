import { describe, expect, it } from "vitest";
import { ADDRESSES } from "@/config/chain";
import type { CubeInstance } from "./types";
import { planRepaymentFunding, type FundingQuote } from "./funding";

const BORROW = 1_000_000n;
const PREMIUM = 500n;

function action(
  key: string,
  cubeId: string,
  inputs: Record<string, string> = {},
  chained = true,
): CubeInstance {
  return { key, cubeId, inputs, chained };
}

function quote(
  amountIn: bigint,
  minimumAmountOut: bigint,
  amountOut: bigint,
): FundingQuote {
  return { status: "ready", amountIn, minimumAmountOut, amountOut };
}

function plan(
  actions: CubeInstance[],
  swapQuotes: Record<string, FundingQuote> = {},
) {
  return planRepaymentFunding({
    actions,
    borrowAmount: BORROW,
    premium: PREMIUM,
    swapQuotes,
  });
}

describe("repayment funding plan", () => {
  it("funds only the premium when the principal remains in the executor", () => {
    expect(plan([])).toEqual({
      automaticFunding: PREMIUM,
      expectedDelta: -PREMIUM,
      intermediateShortfall: null,
    });
  });

  it("funds only the premium after a chained Aave supply and withdraw round trip", () => {
    const result = plan([
      action("supply", "aave-supply", { amount: "" }),
      action("withdraw", "aave-withdraw", { amount: "" }),
    ]);

    expect(result.automaticFunding).toBe(PREMIUM);
    expect(result.expectedDelta).toBe(-PREMIUM);
    expect(result.intermediateShortfall).toBeNull();
  });

  it("uses conservative output for funding and quoted output for expected delta", () => {
    const actions = [
      action("out", "swap", {
        tokenIn: ADDRESSES.usdc,
        tokenOut: ADDRESSES.weth,
      }),
      action("back", "swap", {
        tokenIn: ADDRESSES.weth,
        tokenOut: ADDRESSES.usdc,
      }),
    ];
    const result = plan(actions, {
      out: quote(BORROW, 500_000_000_000_000_000n, 510_000_000_000_000_000n),
      back: quote(500_000_000_000_000_000n, 995_000n, 1_010_000n),
    });

    expect(result.automaticFunding).toBe(5_500n);
    expect(result.expectedDelta).toBe(9_500n);
    expect(result.intermediateShortfall).toBeNull();
  });

  it("does not overfund a partial USDC swap that ends in another asset", () => {
    const result = plan(
      [
        action(
          "partial",
          "swap",
          { tokenIn: ADDRESSES.usdc, tokenOut: ADDRESSES.weth },
          false,
        ),
      ],
      { partial: quote(400_000n, 200_000_000_000_000_000n, 205_000_000_000_000_000n) },
    );

    expect(result.automaticFunding).toBe(400_500n);
    expect(result.expectedDelta).toBe(-400_500n);
  });

  it("accounts for a fixed supply after a two-hop swap", () => {
    const actions = [
      action("out", "swap", {
        tokenIn: ADDRESSES.usdc,
        tokenOut: ADDRESSES.weth,
      }),
      action("back", "swap", {
        tokenIn: ADDRESSES.weth,
        tokenOut: ADDRESSES.usdc,
      }),
      action("supply", "aave-supply", { amount: "0.5" }, false),
    ];
    const result = plan(actions, {
      out: quote(BORROW, 500_000_000_000_000_000n, 510_000_000_000_000_000n),
      back: quote(500_000_000_000_000_000n, 995_000n, 1_010_000n),
    });

    expect(result.automaticFunding).toBe(505_500n);
    expect(result.expectedDelta).toBe(-490_500n);
    expect(result.intermediateShortfall).toBeNull();
  });

  it("uses an explicit add-funds action before adding hidden repayment funding", () => {
    const result = plan([
      action("fund", "add-funds", { amount: "0.05" }, false),
    ]);

    expect(result.automaticFunding).toBe(0n);
    expect(result.expectedDelta).toBe(-PREMIUM);
  });

  it("accounts for USDC returned to the wallet before repayment", () => {
    const result = plan([
      action("return", "return-funds", { token: ADDRESSES.usdc }, false),
    ]);

    expect(result.automaticFunding).toBe(BORROW + PREMIUM);
    expect(result.expectedDelta).toBe(-PREMIUM);
  });

  it("reports an intermediate shortfall that final funding cannot repair", () => {
    const result = plan([
      action("supply", "aave-supply", { amount: "1.1" }, false),
    ]);

    expect(result.intermediateShortfall).toEqual({
      actionIndex: 0,
      asset: "USDC",
      available: BORROW,
      required: 1_100_000n,
    });
  });
});
