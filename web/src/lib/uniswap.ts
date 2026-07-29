import {
  encodeFunctionData,
  parseAbi,
  type Address,
  type Hex,
} from "viem";
import { ADDRESSES, UNISWAP_V3_FEE } from "@/config/chain";

export const uniswapQuoterV2Abi = parseAbi([
  "function quoteExactInputSingle((address tokenIn,address tokenOut,uint256 amountIn,uint24 fee,uint160 sqrtPriceLimitX96) params) returns (uint256 amountOut,uint160 sqrtPriceX96After,uint32 initializedTicksCrossed,uint256 gasEstimate)",
]);

export const uniswapSwapRouter02Abi = parseAbi([
  "function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) payable returns (uint256 amountOut)",
]);

export function tokenDecimals(token: Address) {
  return token.toLowerCase() === ADDRESSES.weth.toLowerCase() ? 18 : 6;
}

export function tokenSymbol(token: Address) {
  const normalized = token.toLowerCase();
  if (normalized === ADDRESSES.usdc.toLowerCase()) return "USDC";
  if (normalized === ADDRESSES.weth.toLowerCase()) return "WETH";
  if (normalized === ADDRESSES.usdt0.toLowerCase()) return "USDT0";
  return "TOKEN";
}

export function minimumOutput(quoted: bigint, slippagePercent: string) {
  const parsed = Number(slippagePercent || "0.5");
  if (!Number.isFinite(parsed) || parsed < 0 || parsed >= 100) {
    throw new Error("Slippage must be between 0% and 100%.");
  }
  const slippageBps = BigInt(Math.round(parsed * 100));
  return (quoted * (10_000n - slippageBps)) / 10_000n;
}

export function encodeUniswapExactInputSingle({
  tokenIn,
  tokenOut,
  recipient,
  amountIn,
  minimumAmountOut,
}: {
  tokenIn: Address;
  tokenOut: Address;
  recipient: Address;
  amountIn: bigint;
  minimumAmountOut: bigint;
}): Hex {
  return encodeFunctionData({
    abi: uniswapSwapRouter02Abi,
    functionName: "exactInputSingle",
    args: [{
      tokenIn,
      tokenOut,
      fee: UNISWAP_V3_FEE,
      recipient,
      amountIn,
      amountOutMinimum: minimumAmountOut,
      sqrtPriceLimitX96: 0n,
    }],
  });
}
