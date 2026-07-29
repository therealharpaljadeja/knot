import {
  BaseError,
  ContractFunctionRevertedError,
  decodeErrorResult,
  parseAbi,
  type Hex,
} from "viem";
import { abis } from "@/generated/contracts";

const FRIENDLY: Record<string, string> = {
  InsufficientOutput: "insufficient output — increase slippage only after checking the quote",
  RouterNotAllowed: "the selected swap router is not allowlisted",
  HandlerNotAllowed: "a cube handler is not registered",
  SafeERC20FailedOperation: "a token transfer or approval failed",
  InvalidInitiator: "the Aave callback initiator was invalid",
};
const standardErrors = parseAbi(["error Error(string)", "error Panic(uint256)"]);

export function explainSimulationError(
  error: unknown,
  swapIndex?: number,
  userActionCount?: number,
): string {
  if (error instanceof BaseError) {
    const reverted = error.walk(
      (candidate) => candidate instanceof ContractFunctionRevertedError,
    );
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName;
      if (name === "InnerActionFailed") {
        const [index, reason] = (reverted.data?.args ?? []) as readonly [
          bigint,
          Hex,
        ];
        try {
          const nested = decodeErrorResult({
            abi: [
              ...standardErrors,
              ...abis.HandlerSwap,
              ...abis.HandlerAaveV3,
              ...abis.HandlerFunds,
              ...abis.FlashLoanHandler,
            ],
            data: reason,
          }) as { errorName: string; args?: readonly unknown[] };
          const revertReason =
            nested.errorName === "Error" &&
            nested.args !== undefined &&
            typeof nested.args[0] === "string"
              ? nested.args[0]
              : undefined;
          const detail =
            revertReason ??
            FRIENDLY[nested.errorName] ??
            nested.errorName.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase();
          const location =
            userActionCount !== undefined && Number(index) >= userActionCount
              ? "Premium funding"
              : `Cube ${Number(index) + 1}`;
          return `${location} would revert: ${detail}.`;
        } catch {
          const location =
            userActionCount !== undefined && Number(index) >= userActionCount
              ? "Premium funding"
              : `Cube ${Number(index) + 1}`;
          return `${location} would revert.`;
        }
      }
      const message = name ? FRIENDLY[name] : undefined;
      if (message) {
        return swapIndex === undefined ? message : `Cube ${swapIndex + 1} would revert: ${message}.`;
      }
      return reverted.reason || reverted.shortMessage;
    }
    return error.shortMessage;
  }
  return error instanceof Error ? error.message : "Simulation failed for an unknown reason.";
}
