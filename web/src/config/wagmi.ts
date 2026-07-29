import { WagmiAdapter } from "@reown/appkit-adapter-wagmi";
import type { AppKitNetwork } from "@reown/appkit/networks";
import { monad } from "./chain";

const configuredProjectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID?.trim();

export const walletConnectConfigured = Boolean(
  configuredProjectId &&
    configuredProjectId !== "replace-with-reown-project-id" &&
    configuredProjectId !== "missing-project-id",
);

export const projectId = walletConnectConfigured
  ? configuredProjectId!
  : "missing-project-id";
export const networks = [monad as AppKitNetwork] as [
  AppKitNetwork,
  ...AppKitNetwork[],
];

export const wagmiAdapter = new WagmiAdapter({
  networks,
  projectId,
  ssr: true,
});
