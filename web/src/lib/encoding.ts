import { encodeFunctionData, type Address, type Hex } from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import type { DeploymentAddresses, EncodedAction } from "./types";

export type EncodedCombo = {
  executor: Address;
  handlers: Address[];
  datas: Hex[];
  data: Hex;
  approvalAmount: bigint;
};

export function encodeCombo({
  amount,
  fundingAmount,
  actions,
  deployments,
}: {
  amount: bigint;
  fundingAmount: bigint;
  actions: EncodedAction[];
  deployments: DeploymentAddresses;
}): EncodedCombo {
  const innerHandlers = actions.map((action) => action.handler);
  const innerDatas = actions.map((action) => action.data);

  if (fundingAmount > 0n) {
    // Fund repayment last so a first action's max sentinel sees only flash principal.
    innerHandlers.push(deployments.HandlerFunds);
    innerDatas.push(
      encodeFunctionData({
        abi: abis.HandlerFunds,
        functionName: "addFunds",
        args: [ADDRESSES.usdc, fundingAmount],
      }),
    );
  }

  const handlers: Address[] = [deployments.FlashLoanHandler];
  const datas: Hex[] = [
    encodeFunctionData({
      abi: abis.FlashLoanHandler,
      functionName: "flashLoan",
      args: [ADDRESSES.usdc, amount, innerHandlers, innerDatas],
    }),
  ];

  return {
    executor: deployments.Executor,
    handlers,
    datas,
    data: encodeFunctionData({
      abi: abis.Executor,
      functionName: "execute",
      args: [handlers, datas],
    }),
    approvalAmount: fundingAmount,
  };
}
