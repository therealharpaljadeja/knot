import { encodeFunctionData } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import type { CubeManifest } from "@/lib/types";

export const returnFundsCube: CubeManifest = {
  id: "return-funds",
  name: "Return funds",
  description: "Send the executor's complete USDC balance back to your wallet.",
  icon: "↗",
  handlerName: "HandlerFunds",
  defaults: { token: ADDRESSES.usdc },
  inputs: [
    { key: "token", label: "Token", kind: "select", options: [{ label: "USDC", value: ADDRESSES.usdc }] },
  ],
  encode(_inputs, deployments) {
    return {
      handler: deployments.HandlerFunds,
      data: encodeFunctionData({
        abi: abis.HandlerFunds,
        functionName: "returnFunds",
        args: [ADDRESSES.usdc],
      }),
    };
  },
};
