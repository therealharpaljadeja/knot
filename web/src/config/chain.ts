import { defineChain } from "viem";

export const monad = defineChain({
  id: 143,
  name: "Monad",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.monad.xyz"] } },
  blockExplorers: {
    default: { name: "Monadscan", url: "https://monadscan.com" },
  },
});

export const ADDRESSES = {
  pool: "0x69a5F9AD4f96ebf0a0C792dD42a01cC5C0102fef",
  dataProvider: "0xB65A68B98274ef7D9a60E0C0747dD1BEc3D32fad",
  usdc: "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
  aUsdc: "0x35a73BAcb179d3740395A3ceCc87FF2e581d6042",
  usdt0: "0xe7cd86e13AC4309349F30B3435a9d337750fC82D",
  weth: "0xEE8c0E9f1BFFb4Eb878d8f15f368A02a35481242",
  uniswapV3Factory: "0x204faca1764b154221e35c0d20abb3c525710498",
  uniswapQuoterV2: "0x661e93cca42afacb172121ef892830ca3b70f08d",
  uniswapSwapRouter02: "0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900",
} as const;

export const UNISWAP_V3_FEE = 3_000;
