import { parseUnits } from "viem";
import { ADDRESSES } from "@/config/chain";
import type { CubeInstance } from "./types";

export type FundingQuote = {
  status: "loading" | "ready" | "error";
  amountIn?: bigint;
  amountOut?: bigint;
  minimumAmountOut?: bigint;
};

export type IntermediateShortfall = {
  actionIndex: number;
  asset: "USDC" | "aUSDC";
  available: bigint;
  required: bigint;
};

export type FundingPlan = {
  automaticFunding: bigint;
  expectedDelta: bigint;
  intermediateShortfall: IntermediateShortfall | null;
};

type PlanningBalance = {
  minimum: bigint;
  expected: bigint;
};

function fixedUsdcAmount(value: string | undefined): bigint {
  if (!value || Number(value) < 0) return 0n;
  try {
    return parseUnits(value, 6);
  } catch {
    return 0n;
  }
}

function isToken(value: string | undefined, token: string): boolean {
  return value?.toLowerCase() === token.toLowerCase();
}

function debit(
  balance: PlanningBalance,
  amount: bigint,
  actionIndex: number,
  asset: IntermediateShortfall["asset"],
): IntermediateShortfall | null {
  if (balance.minimum < amount) {
    return {
      actionIndex,
      asset,
      available: balance.minimum,
      required: amount,
    };
  }
  balance.minimum -= amount;
  balance.expected = balance.expected > amount ? balance.expected - amount : 0n;
  return null;
}

export function planRepaymentFunding({
  actions,
  borrowAmount,
  premium,
  swapQuotes,
  walletBalance = 0n,
}: {
  actions: CubeInstance[];
  borrowAmount: bigint;
  premium: bigint;
  swapQuotes: Record<string, FundingQuote | undefined>;
  walletBalance?: bigint;
}): FundingPlan {
  const usdc: PlanningBalance = { minimum: borrowAmount, expected: borrowAmount };
  const aUsdc: PlanningBalance = { minimum: 0n, expected: 0n };
  let walletDebit = 0n;
  let walletCredit = 0n;
  let intermediateShortfall: IntermediateShortfall | null = null;

  for (const [actionIndex, action] of actions.entries()) {
    if (action.cubeId === "swap") {
      const quote = swapQuotes[action.key];
      if (
        quote?.status !== "ready" ||
        quote.amountIn === undefined ||
        quote.amountOut === undefined ||
        quote.minimumAmountOut === undefined
      ) {
        continue;
      }

      if (isToken(action.inputs.tokenIn, ADDRESSES.usdc)) {
        intermediateShortfall = debit(usdc, quote.amountIn, actionIndex, "USDC");
      }
      if (intermediateShortfall) break;

      if (isToken(action.inputs.tokenOut, ADDRESSES.usdc)) {
        usdc.minimum += quote.minimumAmountOut;
        usdc.expected += quote.amountOut;
      }
      continue;
    }

    if (action.cubeId === "aave-supply") {
      const minimumAmount = action.chained ? usdc.minimum : fixedUsdcAmount(action.inputs.amount);
      const expectedAmount = action.chained ? usdc.expected : minimumAmount;
      if (!action.chained) {
        intermediateShortfall = debit(usdc, minimumAmount, actionIndex, "USDC");
        if (intermediateShortfall) break;
      } else {
        usdc.minimum = 0n;
        usdc.expected = 0n;
      }
      aUsdc.minimum += minimumAmount;
      aUsdc.expected += expectedAmount;
      continue;
    }

    if (action.cubeId === "aave-withdraw") {
      const minimumAmount = action.chained ? aUsdc.minimum : fixedUsdcAmount(action.inputs.amount);
      const expectedAmount = action.chained ? aUsdc.expected : minimumAmount;
      if (!action.chained) {
        intermediateShortfall = debit(aUsdc, minimumAmount, actionIndex, "aUSDC");
        if (intermediateShortfall) break;
      } else {
        aUsdc.minimum = 0n;
        aUsdc.expected = 0n;
      }
      usdc.minimum += minimumAmount;
      usdc.expected += expectedAmount;
      continue;
    }

    if (action.cubeId === "add-funds") {
      const amount = action.chained ? walletBalance : fixedUsdcAmount(action.inputs.amount);
      usdc.minimum += amount;
      usdc.expected += amount;
      walletDebit += amount;
      continue;
    }

    if (action.cubeId === "return-funds") {
      walletCredit += usdc.expected;
      usdc.minimum = 0n;
      usdc.expected = 0n;
    }
  }

  const repayment = borrowAmount + premium;
  const automaticFunding = usdc.minimum < repayment ? repayment - usdc.minimum : 0n;
  const expectedAfterRepayment = usdc.expected + automaticFunding;
  const expectedResidual =
    expectedAfterRepayment > repayment ? expectedAfterRepayment - repayment : 0n;
  const expectedDelta = walletCredit + expectedResidual - walletDebit - automaticFunding;

  return { automaticFunding, expectedDelta, intermediateShortfall };
}
