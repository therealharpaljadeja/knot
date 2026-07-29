import { encodeFunctionData } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import { parseTokenAmount } from "@/lib/amount";
import type { CubeManifest } from "@/lib/types";

export const aaveSupplyCube: CubeManifest = {
  id: "aave-supply",
  name: "Aave supply",
  description: "Supply USDC to Aave v3 from the executor.",
  icon: "↓",
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
        functionName: "supply",
        args: [ADDRESSES.usdc, parseTokenAmount(inputs.amount, 6, inputs.chained === "true")],
      }),
    };
  },
};
