import { maxUint256, parseUnits } from "viem";

export function parseTokenAmount(
  value: string,
  decimals = 6,
  chained = false,
): bigint {
  if (chained) return maxUint256;
  if (!value || Number(value) < 0) throw new Error("Enter a valid amount.");
  return parseUnits(value, decimals);
}
