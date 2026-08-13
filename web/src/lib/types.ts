import type { Address, Hex } from "viem";

export type ContractName =
  | "Registry"
  | "RegistryTimelock"
  | "Executor"
  | "FlashLoanHandler"
  | "HandlerAaveV3"
  | "HandlerSwap"
  | "HandlerFunds";

export type DeploymentAddresses = Record<ContractName, Address>;

export type FieldKind = "amount" | "address" | "select" | "bytes" | "percent";

export type CubeField = {
  key: string;
  label: string;
  kind: FieldKind;
  placeholder?: string;
  options?: { label: string; value: string }[];
  defaultValue?: string;
  allowChained?: boolean;
};

export type EncodedAction = { handler: Address; data: Hex };

export type CubeManifest = {
  id: string;
  name: string;
  description: string;
  icon: string;
  handlerName: ContractName;
  inputs: CubeField[];
  defaults: Record<string, string>;
  encode(inputs: Record<string, string>, deployments: DeploymentAddresses): EncodedAction;
};

export type CubeInstance = {
  key: string;
  cubeId: string;
  inputs: Record<string, string>;
  chained: boolean;
};
