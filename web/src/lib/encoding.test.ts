import { describe, expect, it } from "vitest";
import {
  decodeFunctionData,
  encodeFunctionData,
  keccak256,
  maxUint256,
  type Address,
} from "viem";
import { abis } from "@/generated/contracts";
import { ADDRESSES } from "@/config/chain";
import { aaveRepayCube } from "@/cubes/aave-repay";
import fixture from "./__fixtures__/foundry-roundtrip.json";
import { encodeCombo } from "./encoding";
import type { DeploymentAddresses } from "./types";

const addresses: DeploymentAddresses = {
  Registry: "0x5555555555555555555555555555555555555555",
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

  it("matches the Foundry fixture for a repay deleverage combo", () => {
    // Same four inner actions as PrintCalldata's repay case: clear the debt with the flash
    // principal, pull the freed collateral in as aUSDC, withdraw it as USDC, then fund the
    // premium. encodeCombo appends that last funding call itself.
    const actions = [
      {
        handler: addresses.HandlerAaveV3,
        data: encodeFunctionData({
          abi: abis.HandlerAaveV3,
          functionName: "repay",
          args: [ADDRESSES.usdc, maxUint256],
        }),
      },
      {
        handler: addresses.HandlerFunds,
        data: encodeFunctionData({
          abi: abis.HandlerFunds,
          functionName: "addFunds",
          args: [ADDRESSES.aUsdc, BigInt(fixture.repay.collateralFunding)],
        }),
      },
      {
        handler: addresses.HandlerAaveV3,
        data: encodeFunctionData({
          abi: abis.HandlerAaveV3,
          functionName: "withdraw",
          args: [ADDRESSES.usdc, maxUint256],
        }),
      },
    ];

    const combo = encodeCombo({
      amount: BigInt(fixture.repay.flashAmount),
      fundingAmount: BigInt(fixture.repay.premium),
      actions,
      deployments: addresses,
    });

    expect(keccak256(combo.data)).toBe(fixture.repay.calldataKeccak256);
  });

  it("encodes the repay cube against the Aave handler", () => {
    const action = aaveRepayCube.encode(
      { asset: ADDRESSES.usdc, amount: "1.5", chained: "false" },
      addresses,
    );
    const decoded = decodeFunctionData({ abi: abis.HandlerAaveV3, data: action.data });

    expect(action.handler).toBe(addresses.HandlerAaveV3);
    expect(decoded.functionName).toBe("repay");
    expect(decoded.args).toEqual([ADDRESSES.usdc, 1_500_000n]);
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
});
