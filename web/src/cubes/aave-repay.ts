import { encodeFunctionData } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import { parseTokenAmount } from "@/lib/amount";
import type { CubeManifest } from "@/lib/types";

export const aaveRepayCube: CubeManifest = {
  id: "aave-repay",
  name: "Aave repay",
  description: "Repay your wallet's Aave v3 USDC debt from the executor.",
  icon: "↩",
  handlerName: "HandlerAaveV3",
  defaults: { asset: ADDRESSES.usdc, amount: "", chained: "true" },
  inputs: [
    { key: "asset", label: "Asset", kind: "select", options: [{ label: "USDC", value: ADDRESSES.usdc }] },
    { key: "amount", label: "Amount", kind: "amount", allowChained: true },
  ],
  encode(inputs, deployments) {
    return {
      handler: deployments.HandlerAaveV3,
      data: encodeFunctionData({
        abi: abis.HandlerAaveV3,
        functionName: "repay",
        args: [ADDRESSES.usdc, parseTokenAmount(inputs.amount, 6, inputs.chained === "true")],
      }),
    };
  },
};
