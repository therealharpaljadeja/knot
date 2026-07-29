import { aaveSupplyCube } from "./aave-supply";
import { aaveWithdrawCube } from "./aave-withdraw";
import { addFundsCube } from "./add-funds";
import { returnFundsCube } from "./return-funds";
import { swapCube } from "./swap";

export const cubeManifests = [
  swapCube,
  aaveSupplyCube,
  aaveWithdrawCube,
  addFundsCube,
  returnFundsCube,
] as const;

export const cubesById = Object.fromEntries(
  cubeManifests.map((cube) => [cube.id, cube]),
);
