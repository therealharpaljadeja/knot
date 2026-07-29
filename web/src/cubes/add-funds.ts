import { encodeFunctionData } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import { parseTokenAmount } from "@/lib/amount";
import type { CubeManifest } from "@/lib/types";

export const addFundsCube: CubeManifest = {
  id: "add-funds",
  name: "Add funds",
  description: "Pull an exact amount from your wallet during this transaction.",
  icon: "+",
  handlerName: "HandlerFunds",
  defaults: { token: ADDRESSES.usdc, amount: "", chained: "false" },
  inputs: [
    { key: "token", label: "Token", kind: "select", options: [{ label: "USDC", value: ADDRESSES.usdc }] },
    { key: "amount", label: "Amount", kind: "amount", allowChained: true },
  ],
  encode(inputs, deployments) {
    return {
      handler: deployments.HandlerFunds,
      data: encodeFunctionData({
        abi: abis.HandlerFunds,
        functionName: "addFunds",
        args: [ADDRESSES.usdc, parseTokenAmount(inputs.amount, 6, inputs.chained === "true")],
      }),
    };
  },
};
