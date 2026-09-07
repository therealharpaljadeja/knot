import { describe, expect, it } from "vitest";
import {
  ContractFunctionRevertedError,
  encodeErrorResult,
  parseAbi,
} from "viem";
import { abis } from "@/generated/contracts";
import { explainSimulationError } from "./errors";

const standardErrors = parseAbi(["error Error(string)"]);

function innerFailure(index: number) {
  const reason = encodeErrorResult({
    abi: standardErrors,
    errorName: "Error",
    args: ["forced failure"],
  });
  const data = encodeErrorResult({
    abi: abis.FlashLoanHandler,
    errorName: "InnerActionFailed",
    args: [BigInt(index), reason],
  });
  return new ContractFunctionRevertedError({
    abi: abis.FlashLoanHandler,
    data,
    functionName: "executeOperation",
  });
}

describe("three-action simulation attribution", () => {
  it.each([
    [0, "Cube 1 would revert: forced failure."],
    [1, "Cube 2 would revert: forced failure."],
    [2, "Cube 3 would revert: forced failure."],
    [3, "Premium funding would revert: forced failure."],
  ])("labels inner action index %i", (index, expected) => {
    expect(explainSimulationError(innerFailure(index), undefined, 3)).toBe(expected);
  });
});
