import { describe, expect, it } from "vitest";
import { decodeFunctionData } from "viem";
import { ADDRESSES, UNISWAP_V3_FEE } from "@/config/chain";
import {
  encodeUniswapExactInputSingle,
  minimumOutput,
  uniswapSwapRouter02Abi,
} from "./uniswap";

describe("Uniswap testing-mode encoding", () => {
  it("uses the previous swap minimum as a conservative chained input", () => {
    expect(minimumOutput(1_000_000n, "0.5")).toBe(995_000n);
  });

  it("encodes the fixed Monad SwapRouter02 exact-input call", () => {
    const data = encodeUniswapExactInputSingle({
      tokenIn: ADDRESSES.usdc,
      tokenOut: ADDRESSES.weth,
      recipient: "0xb34C788AC3b5D4e3159Ad0084d53786BbD7870b5",
      amountIn: 1_000_000n,
      minimumAmountOut: 400_000_000_000_000n,
    });
    const decoded = decodeFunctionData({ abi: uniswapSwapRouter02Abi, data });

    expect(decoded.functionName).toBe("exactInputSingle");
    expect(decoded.args[0]).toMatchObject({
      tokenIn: ADDRESSES.usdc,
      tokenOut: ADDRESSES.weth,
      fee: UNISWAP_V3_FEE,
      amountIn: 1_000_000n,
      amountOutMinimum: 400_000_000_000_000n,
    });
  });
});
