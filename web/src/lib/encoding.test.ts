import { describe, expect, it } from "vitest";
import {
  decodeFunctionData,
  encodeFunctionData,
  keccak256,
  maxUint256,
  type Address,
  type Hex,
} from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import fixture from "./__fixtures__/foundry-roundtrip.json";
import { encodeCombo } from "./encoding";
import type { DeploymentAddresses } from "./types";

const addresses: DeploymentAddresses = {
  Registry: "0x5555555555555555555555555555555555555555",
  RegistryTimelock: "0x7777777777777777777777777777777777777777",
  Executor: "0x4444444444444444444444444444444444444444",
  FlashLoanHandler: "0x1111111111111111111111111111111111111111",
  HandlerAaveV3: "0x2222222222222222222222222222222222222222",
  HandlerSwap: "0x6666666666666666666666666666666666666666",
  HandlerFunds: "0x3333333333333333333333333333333333333333",
};

describe("combo encoding", () => {
  it("matches the calldata hash emitted by the Foundry fixture script", () => {
    const actions = (["supply", "withdraw"] as const).map((functionName) => ({
      handler: addresses.HandlerAaveV3,
      data: encodeFunctionData({
        abi: abis.HandlerAaveV3,
        functionName,
        args: [ADDRESSES.usdc, maxUint256],
      }),
    }));

    const combo = encodeCombo({
      amount: BigInt(fixture.flashAmount),
      fundingAmount: BigInt(fixture.premium),
      actions,
      deployments: addresses,
    });

    expect(keccak256(combo.data)).toBe(fixture.calldataKeccak256);
  });

  it("encodes a zero-premium smoke test as one outer flash-loan handler", () => {
    const combo = encodeCombo({
      amount: 1_000_000n,
      fundingAmount: 0n,
      actions: [],
      deployments: addresses,
    });
    const decoded = decodeFunctionData({ abi: abis.Executor, data: combo.data });
    const [handlers, datas] = decoded.args as readonly [Address[], `0x${string}`[]];

    expect(handlers).toEqual([addresses.FlashLoanHandler]);
    expect(datas).toHaveLength(1);
    expect(combo.approvalAmount).toBe(0n);
  });

  it("keeps exact premium funding inside the flash loan after user actions", () => {
    const combo = encodeCombo({
      amount: 2_000_000n,
      fundingAmount: 1_000n,
      actions: [],
      deployments: addresses,
    });

    expect(combo.handlers).toEqual([addresses.FlashLoanHandler]);
    expect(combo.approvalAmount).toBe(1_000n);
  });

  it("preserves three user actions before the hidden repayment funding action", () => {
    const userHandlers = [
      addresses.HandlerSwap,
      addresses.HandlerAaveV3,
      addresses.HandlerSwap,
    ];
    const userDatas = ["0x01", "0x02", "0x03"] as Hex[];
    const combo = encodeCombo({
      amount: 1_000_000n,
      fundingAmount: 500n,
      actions: userHandlers.map((handler, index) => ({
        handler,
        data: userDatas[index]!,
      })),
      deployments: addresses,
    });

    const outer = decodeFunctionData({ abi: abis.FlashLoanHandler, data: combo.datas[0]! });
    const [, , innerHandlers, innerDatas] = outer.args as readonly [
      Address,
      bigint,
      Address[],
      Hex[],
    ];

    expect(innerHandlers.slice(0, 3)).toEqual(userHandlers);
    expect(innerDatas.slice(0, 3)).toEqual(userDatas);
    expect(innerHandlers[3]).toBe(addresses.HandlerFunds);
    expect(innerDatas).toHaveLength(4);
  });
});
