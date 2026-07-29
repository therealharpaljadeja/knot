import { encodeFunctionData, getAddress, parseUnits } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import { parseTokenAmount } from "@/lib/amount";
import { minimumOutput, tokenDecimals } from "@/lib/uniswap";
import type { CubeManifest } from "@/lib/types";

export const swapCube: CubeManifest = {
  id: "swap",
  name: "Swap",
  description: "Route an exact-input swap through an allowlisted venue.",
  icon: "⇄",
  handlerName: "HandlerSwap",
  defaults: {
    tokenIn: ADDRESSES.usdc,
    tokenOut: ADDRESSES.weth,
    amount: "",
    expectedOut: "",
    slippage: "0.5",
    routeData: "0x",
    chained: "true",
  },
  inputs: [
    {
      key: "tokenIn",
      label: "Token in",
      kind: "select",
      options: [
        { label: "USDC", value: ADDRESSES.usdc },
        { label: "WETH", value: ADDRESSES.weth },
        { label: "USDT0", value: ADDRESSES.usdt0 },
      ],
    },
    {
      key: "tokenOut",
      label: "Token out",
      kind: "select",
      options: [
        { label: "WETH", value: ADDRESSES.weth },
        { label: "USDC", value: ADDRESSES.usdc },
        { label: "USDT0", value: ADDRESSES.usdt0 },
      ],
    },
    { key: "amount", label: "Amount in", kind: "amount", allowChained: true },
    { key: "slippage", label: "Slippage", kind: "percent", defaultValue: "0.5" },
  ],
  encode(inputs, deployments) {
    const tokenIn = getAddress(inputs.tokenIn);
    const tokenOut = getAddress(inputs.tokenOut);
    const inDecimals = tokenDecimals(tokenIn);
    const outDecimals = tokenDecimals(tokenOut);
    const amountIn = parseTokenAmount(inputs.amount, inDecimals, inputs.chained === "true");
    const quoted = parseUnits(inputs.expectedOut || "0", outDecimals);
    const minOut = minimumOutput(quoted, inputs.slippage);
    return {
      handler: deployments.HandlerSwap,
      data: encodeFunctionData({
        abi: abis.HandlerSwap,
        functionName: "swapExactIn",
        args: [
          ADDRESSES.uniswapSwapRouter02,
          tokenIn,
          tokenOut,
          amountIn,
          minOut,
          inputs.routeData as `0x${string}`,
        ],
      }),
    };
  },
};
