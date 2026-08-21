"use client";

import {
  AlertTriangle,
  Check,
  ChevronDown,
  CircleDollarSign,
  ExternalLink,
  LoaderCircle,
  LockKeyhole,
  Plus,
  Trash2,
  WalletCards,
  Zap,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  formatUnits,
  getAddress,
  maxUint256,
  parseAbi,
  parseUnits,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useReadContract,
  useSimulateContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { useAppKit } from "@reown/appkit/react";
import { ADDRESSES, UNISWAP_V3_FEE } from "@/config/chain";
import { walletConnectConfigured } from "@/config/wagmi";
import { abis, deployments as generatedDeployments } from "@/generated/contracts";
import { cubeManifests, cubesById } from "@/cubes";
import { MAX_ACTIONS } from "@/lib/actions";
import { encodeCombo } from "@/lib/encoding";
import { explainSimulationError } from "@/lib/errors";
import { planRepaymentFunding } from "@/lib/funding";
import {
  encodeUniswapExactInputSingle,
  minimumOutput,
  tokenDecimals,
  tokenSymbol,
  uniswapQuoterV2Abi,
} from "@/lib/uniswap";
import type { CubeInstance, DeploymentAddresses } from "@/lib/types";

const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
]);
const poolAbi = parseAbi(["function FLASHLOAN_PREMIUM_TOTAL() view returns (uint128)"]);
const simulationAbi = [
  ...abis.Executor,
  ...abis.FlashLoanHandler,
  ...abis.HandlerSwap,
  ...abis.HandlerAaveV3,
  ...abis.HandlerFunds,
] as const;
const configured = generatedDeployments["143"] as DeploymentAddresses;
const deployed = configured.Executor !== zeroAddress;

type SwapQuoteState = {
  status: "loading" | "ready" | "error";
  amountIn?: bigint;
  amountOut?: bigint;
  minimumAmountOut?: bigint;
  routeData?: Hex;
  message?: string;
};

const makeCube = (cubeId: string, overrides: Record<string, string> = {}): CubeInstance => {
  const manifest = cubesById[cubeId];
  return {
    key: crypto.randomUUID(),
    cubeId,
    inputs: { ...manifest.defaults, ...overrides },
    chained: manifest.defaults.chained === "true",
  };
};

function shortAddress(address?: string) {
  return address ? `${address.slice(0, 6)}…${address.slice(-4)}` : "";
}

function formatUsdc(value?: bigint) {
  return value === undefined
    ? "—"
    : Number(formatUnits(value, 6)).toLocaleString(undefined, {
        maximumFractionDigits: 6,
      });
}

function formatTokenAmount(value: bigint, token: Address) {
  return Number(formatUnits(value, tokenDecimals(token))).toLocaleString(undefined, {
    maximumFractionDigits: tokenDecimals(token) === 18 ? 8 : 6,
  });
}

export default function BuilderPage() {
  const mainnetNoticeRef = useRef<HTMLDialogElement>(null);
  const [mainnetNoticeAccepted, setMainnetNoticeAccepted] = useState<boolean | null>(null);
  const { open } = useAppKit();
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const [borrowInput, setBorrowInput] = useState("1");
  const [actions, setActions] = useState<CubeInstance[]>([]);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [flowError, setFlowError] = useState("");
  const [phase, setPhase] = useState<"idle" | "approving" | "sending">("idle");
  const [swapQuotes, setSwapQuotes] = useState<Record<string, SwapQuoteState>>({});
  const hasSwap = actions.some((action) => action.cubeId === "swap");

  useEffect(() => {
    setMainnetNoticeAccepted(false);
    if (!mainnetNoticeRef.current?.open) {
      mainnetNoticeRef.current?.showModal();
    }
  }, []);

  function acceptMainnetNotice() {
    setMainnetNoticeAccepted(true);
    mainnetNoticeRef.current?.close();
  }

  const readsEnabled = deployed && chainId === 143;
  const premiumRead = useReadContract({
    address: ADDRESSES.pool,
    abi: poolAbi,
    functionName: "FLASHLOAN_PREMIUM_TOTAL",
    chainId: 143,
    query: { enabled: readsEnabled, staleTime: Infinity },
  });
  const liquidityRead = useReadContract({
    address: ADDRESSES.usdc,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [ADDRESSES.aUsdc],
    chainId: 143,
    query: {
      enabled: readsEnabled,
      staleTime: 10_000,
      refetchInterval: 15_000,
      refetchOnWindowFocus: "always",
    },
  });
  const walletBalanceRead = useReadContract({
    address: ADDRESSES.usdc,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [address ?? zeroAddress],
    chainId: 143,
    query: {
      enabled: readsEnabled && Boolean(address),
      staleTime: 2_000,
      refetchInterval: isConnected ? 4_000 : false,
      refetchOnWindowFocus: "always",
      refetchOnReconnect: "always",
    },
  });
  const routerAllowedRead = useReadContract({
    address: configured.Registry,
    abi: abis.Registry,
    functionName: "routers",
    args: [ADDRESSES.uniswapSwapRouter02],
    chainId: 143,
    query: {
      enabled: readsEnabled && hasSwap,
      staleTime: 15_000,
      refetchInterval: hasSwap ? 30_000 : false,
      refetchOnWindowFocus: "always",
    },
  });

  const borrowAmount = useMemo(() => {
    try {
      return parseUnits(borrowInput || "0", 6);
    } catch {
      return 0n;
    }
  }, [borrowInput]);
  const premiumBps = premiumRead.data ?? 0n;
  const premium = (borrowAmount * premiumBps + 5_000n) / 10_000n;

  useEffect(() => {
    const swapActions = actions.filter((action) => action.cubeId === "swap");
    if (swapActions.length === 0) {
      setSwapQuotes({});
      return;
    }

    setSwapQuotes(Object.fromEntries(
      swapActions.map((action) => [action.key, { status: "loading" as const }]),
    ));

    let cancelled = false;
    const quoteTimer = window.setTimeout(async () => {
      const nextQuotes: Record<string, SwapQuoteState> = {};
      let previousMinimum = borrowAmount;
      let previousToken: Address = ADDRESSES.usdc;

      for (const action of actions) {
        if (action.cubeId !== "swap") {
          previousMinimum = 0n;
          continue;
        }

        try {
          if (!publicClient) throw new Error("Monad RPC is not ready.");

          const tokenIn = getAddress(action.inputs.tokenIn);
          const tokenOut = getAddress(action.inputs.tokenOut);
          if (tokenIn === tokenOut) throw new Error("Choose two different tokens.");

          let quoteAmountIn: bigint;
          if (action.chained) {
            if (previousMinimum <= 0n || previousToken.toLowerCase() !== tokenIn.toLowerCase()) {
              throw new Error("Previous output does not match this input token.");
            }
            quoteAmountIn = previousMinimum;
          } else {
            quoteAmountIn = parseUnits(action.inputs.amount || "0", tokenDecimals(tokenIn));
          }
          if (quoteAmountIn <= 0n) throw new Error("Enter an amount to quote.");

          const { result } = await publicClient.simulateContract({
            address: ADDRESSES.uniswapQuoterV2,
            abi: uniswapQuoterV2Abi,
            functionName: "quoteExactInputSingle",
            args: [{
              tokenIn,
              tokenOut,
              amountIn: quoteAmountIn,
              fee: UNISWAP_V3_FEE,
              sqrtPriceLimitX96: 0n,
            }],
            account: configured.Executor,
          });
          const amountOut = result[0];
          const minimumAmountOut = minimumOutput(amountOut, action.inputs.slippage);
          const routeData = encodeUniswapExactInputSingle({
            tokenIn,
            tokenOut,
            recipient: configured.Executor,
            amountIn: quoteAmountIn,
            minimumAmountOut,
          });

          nextQuotes[action.key] = {
            status: "ready",
            amountIn: quoteAmountIn,
            amountOut,
            minimumAmountOut,
            routeData,
          };
          previousMinimum = minimumAmountOut;
          previousToken = tokenOut;
        } catch (error) {
          nextQuotes[action.key] = {
            status: "error",
            message: error instanceof Error ? error.message : "Quote unavailable.",
          };
          previousMinimum = 0n;
        }
      }

      if (!cancelled) setSwapQuotes(nextQuotes);
    }, 300);

    return () => {
      cancelled = true;
      window.clearTimeout(quoteTimer);
    };
  }, [actions, borrowAmount, publicClient]);

  const encodedActions = useMemo(() => {
    try {
      return actions.map((action) => {
        const manifest = cubesById[action.cubeId];
        const quote = swapQuotes[action.key];
        if (action.cubeId === "swap" && quote?.status !== "ready") {
          throw new Error("Swap quote is not ready.");
        }
        return manifest.encode(
          {
            ...action.inputs,
            chained: String(action.chained),
            ...(quote?.status === "ready"
              ? {
                  expectedOut: formatUnits(
                    quote.amountOut!,
                    tokenDecimals(getAddress(action.inputs.tokenOut)),
                  ),
                  routeData: quote.routeData!,
                }
              : {}),
          },
          configured,
        );
      });
    } catch {
      return null;
    }
  }, [actions, swapQuotes]);

  const fundingPlan = useMemo(
    () =>
      planRepaymentFunding({
        actions,
        borrowAmount,
        premium,
        swapQuotes,
        walletBalance: walletBalanceRead.data,
      }),
    [actions, borrowAmount, premium, swapQuotes, walletBalanceRead.data],
  );
  const { automaticFunding, expectedDelta, intermediateShortfall } = fundingPlan;

  const combo = useMemo(() => {
    if (!encodedActions || borrowAmount <= 0n || !deployed) return null;
    try {
      return encodeCombo({
        amount: borrowAmount,
        fundingAmount: automaticFunding,
        actions: encodedActions,
        deployments: configured,
      });
    } catch {
      return null;
    }
  }, [automaticFunding, borrowAmount, encodedActions]);

  const explicitFunding = useMemo(() => {
    let fixed = 0n;
    let usesWalletMax = false;
    for (const action of actions) {
      if (action.cubeId !== "add-funds") continue;
      if (action.chained) usesWalletMax = true;
      else {
        try {
          fixed += parseUnits(action.inputs.amount || "0", 6);
        } catch {
          // Invalid inputs are handled by encoding and simulation state.
        }
      }
    }
    return { fixed, usesWalletMax };
  }, [actions]);
  const approvalAmount = explicitFunding.usesWalletMax
    ? (walletBalanceRead.data ?? 0n)
    : automaticFunding + explicitFunding.fixed;

  const allowanceRead = useReadContract({
    address: ADDRESSES.usdc,
    abi: erc20Abi,
    functionName: "allowance",
    args: [address ?? zeroAddress, configured.Executor],
    chainId: 143,
    query: {
      enabled: readsEnabled && Boolean(address) && deployed,
      staleTime: 2_000,
      refetchInterval: isConnected ? 4_000 : false,
      refetchOnWindowFocus: "always",
      refetchOnReconnect: "always",
    },
  });
  const currentAllowance = allowanceRead.data ?? 0n;
  const needsApproval =
    approvalAmount > 0n
      ? currentAllowance !== approvalAmount
      : currentAllowance > 0n;
  const insufficientWalletFunds =
    walletBalanceRead.data !== undefined &&
    approvalAmount > walletBalanceRead.data;
  const amountOverLiquidity =
    liquidityRead.data !== undefined && borrowAmount > liquidityRead.data;
  const wrongChain = isConnected && chainId !== 143;
  const swapIndex = actions.findIndex((action) => action.cubeId === "swap");
  const routerNotAllowed = hasSwap && routerAllowedRead.data === false;
  const swapQuotePending = actions.some((action) => {
    if (action.cubeId !== "swap") return false;
    const status = swapQuotes[action.key]?.status;
    return status !== "ready" && status !== "error";
  });
  const swapQuoteError = actions
    .map((action, index) => ({ action, index, quote: swapQuotes[action.key] }))
    .find(({ action, quote }) => action.cubeId === "swap" && quote?.status === "error");

  const simulation = useSimulateContract({
    address: configured.Executor,
    abi: simulationAbi,
    functionName: "execute",
    args: combo ? [combo.handlers, combo.datas] : undefined,
    account: address,
    chainId: 143,
    query: {
      enabled:
        Boolean(combo) &&
        readsEnabled &&
        Boolean(address) &&
        !needsApproval &&
        !insufficientWalletFunds &&
        !amountOverLiquidity &&
        !routerNotAllowed &&
        !intermediateShortfall,
      retry: false,
    },
  });
  const approvalWrite = useWriteContract();
  const comboWrite = useWriteContract();
  const transactionHash = comboWrite.data;
  const receipt = useWaitForTransactionReceipt({
    hash: transactionHash,
    chainId: 143,
    pollingInterval: 250,
    query: { enabled: Boolean(transactionHash) },
  });

  useEffect(() => {
    if (!receipt.isSuccess) return;

    setPhase("idle");
    void walletBalanceRead.refetch();
    void allowanceRead.refetch();

    const resetConfirmation = window.setTimeout(() => {
      comboWrite.reset();
    }, 3_000);

    return () => window.clearTimeout(resetConfirmation);
  }, [receipt.isSuccess]);

  const simulationMessage = simulation.error
    ? explainSimulationError(
        simulation.error,
        swapIndex >= 0 ? swapIndex : undefined,
        actions.length,
      )
    : "";
  const ready =
    Boolean(simulation.data?.request) &&
    !needsApproval &&
    !amountOverLiquidity &&
    !routerNotAllowed &&
    !intermediateShortfall;

  function applyPreset(id: "smoke" | "roundtrip" | "twohop") {
    setFlowError("");
    setPickerOpen(false);
    if (id === "smoke") setActions([]);
    if (id === "roundtrip") {
      setActions([makeCube("aave-supply"), makeCube("aave-withdraw")]);
    }
    if (id === "twohop") {
      setActions([
        makeCube("swap", { tokenIn: ADDRESSES.usdc, tokenOut: ADDRESSES.weth }),
        makeCube("swap", { tokenIn: ADDRESSES.weth, tokenOut: ADDRESSES.usdc }),
      ]);
    }
  }

  async function approveExact() {
    if (!address || approvalAmount <= 0n) return;
    setFlowError("");
    setPhase("approving");
    try {
      const hash = await approvalWrite.writeContractAsync({
        address: ADDRESSES.usdc,
        abi: erc20Abi,
        functionName: "approve",
        args: [configured.Executor, approvalAmount],
        chainId: 143,
        account: address,
      });
      await publicClient?.waitForTransactionReceipt({ hash, pollingInterval: 250 });
      await allowanceRead.refetch();
    } catch (error) {
      setFlowError(error instanceof Error ? error.message : "Approval failed.");
    } finally {
      setPhase("idle");
    }
  }

  async function sendCombo() {
    if (!simulation.data?.request) return;
    setFlowError("");
    setPhase("sending");
    try {
      await comboWrite.writeContractAsync(simulation.data.request);
    } catch (error) {
      setFlowError(error instanceof Error ? error.message : "Transaction failed.");
      setPhase("idle");
    }
  }

  const status = !deployed
    ? "Contracts not deployed yet"
    : wrongChain
      ? "Wrong network"
      : premiumRead.isPending || liquidityRead.isPending
        ? "Reading Monad…"
        : premiumRead.error || liquidityRead.error
          ? "RPC unavailable"
          : "Monad mainnet";

  return (
    <main>
      {mainnetNoticeAccepted === null && <div className="notice-boot-shield" aria-hidden="true" />}
      <dialog
        ref={mainnetNoticeRef}
        className="mainnet-dialog"
        aria-labelledby="mainnet-dialog-title"
        aria-describedby="mainnet-dialog-description"
        onCancel={(event) => event.preventDefault()}
      >
        <div className="mainnet-dialog-content">
          <span className="mainnet-dialog-icon"><AlertTriangle size={20} /></span>
          <span className="mainnet-dialog-eyebrow">Before you continue</span>
          <h2 id="mainnet-dialog-title">Knot uses Monad mainnet</h2>
          <p id="mainnet-dialog-description">
            Transactions use real assets, and the contracts have not been independently audited.
            Review each wallet request and start with a small amount.
          </p>
          <button autoFocus onClick={acceptMainnetNotice}>I understand</button>
          <small>Confirmation is required each time the app is opened.</small>
        </div>
      </dialog>

      <div
        className="app-content"
        inert={mainnetNoticeAccepted !== true}
        aria-hidden={mainnetNoticeAccepted !== true}
      >
        <nav className="topbar">
          <a className="brand" href="#" aria-label="Knot home">
            <span className="brand-mark"><Zap size={17} fill="currentColor" /></span>
            Knot
          </a>
          <div className="nav-right">
            <span className={`network-pill ${readsEnabled ? "online" : ""}`}>
              <span className="status-dot" /> {status === "Monad mainnet" ? "Monad" : status}
            </span>
            <button
              className="wallet-button"
              onClick={() => (walletConnectConfigured || isConnected) && open()}
              disabled={!walletConnectConfigured && !isConnected}
            >
              <WalletCards size={16} />
              {isConnected
                ? shortAddress(address)
                : walletConnectConfigured
                  ? "Connect wallet"
                  : "Wallet setup required"}
            </button>
          </div>
        </nav>

        <section className="app-shell">
          <header className="app-heading">
            <h1>Flash loan combo</h1>
            <p>Borrow USDC, add up to {MAX_ACTIONS} actions, and repay atomically.</p>
          </header>

          <div className="workspace">
        <div className="builder-column">
          <div className="section-head">
            <div className="preset-row">
              <button onClick={() => applyPreset("smoke")}>Smoke</button>
              <button onClick={() => applyPreset("roundtrip")}>Aave round trip</button>
              <button onClick={() => applyPreset("twohop")}>Two-hop swap</button>
            </div>
            <span className="cube-count">{actions.length} / {MAX_ACTIONS} actions</span>
          </div>

          <div className="canvas">
            <div className="rail" />
            <article className="cube pinned borrow">
              <div className="cube-index"><CircleDollarSign size={18} /></div>
              <div className="cube-body">
                <div className="cube-title-row">
                  <div><span className="pin-label">BORROW</span><h2>USDC</h2></div>
                  <span className="protocol">Aave v3</span>
                </div>
                <div className="amount-field">
                  <input
                    value={borrowInput}
                    inputMode="decimal"
                    onChange={(event) => setBorrowInput(event.target.value)}
                    aria-label="USDC flash loan amount"
                  />
                  <span>USDC</span>
                  <button
                    onClick={() => liquidityRead.data !== undefined && setBorrowInput(formatUnits(liquidityRead.data, 6))}
                    disabled={liquidityRead.data === undefined}
                  >MAX</button>
                </div>
                <div className="metric-line">
                  <span>Available liquidity</span>
                  <strong>{liquidityRead.isError ? "Read failed" : `${formatUsdc(liquidityRead.data)} USDC`}</strong>
                </div>
              </div>
            </article>

            {actions.map((action, index) => (
              <ActionCube
                key={action.key}
                action={action}
                index={index}
                swapQuote={swapQuotes[action.key]}
                onChange={(next) => setActions((current) => current.map((item) => item.key === next.key ? next : item))}
                onRemove={() => setActions((current) => current.filter((item) => item.key !== action.key))}
              />
            ))}

            {actions.length < MAX_ACTIONS && (
              <div className="add-wrap">
                <button className="add-cube" onClick={() => setPickerOpen((value) => !value)}>
                  <Plus size={18} /> Add action <ChevronDown size={15} />
                </button>
                {pickerOpen && (
                  <div className="cube-picker">
                    {cubeManifests.map((manifest) => (
                      <button
                        key={manifest.id}
                        onClick={() => {
                          setActions((current) => [...current, makeCube(manifest.id)]);
                          setPickerOpen(false);
                        }}
                      >
                        <span>{manifest.icon}</span>
                        <div><strong>{manifest.name}</strong><small>{manifest.description}</small></div>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            <article className="cube pinned repay">
              <div className="cube-index"><LockKeyhole size={18} /></div>
              <div className="cube-body">
                <div className="cube-title-row">
                  <div><span className="pin-label">AUTOMATIC</span><h2>Repay USDC</h2></div>
                  <span className="protocol">Aave v3</span>
                </div>
                <div className="repay-grid">
                  <div><span>Principal</span><strong>{formatUsdc(borrowAmount)} USDC</strong></div>
                  <div><span>Live premium</span><strong>{premiumRead.isError ? "Read failed" : `${premiumBps.toString()} bps · ${formatUsdc(premium)} USDC`}</strong></div>
                </div>
              </div>
            </article>
          </div>
        </div>

        <aside className="review">
          <div className="review-head"><span>Review</span><span className="review-amount">{formatUsdc(borrowAmount)} USDC</span></div>
          {!deployed && (
            <div className="notice warning">
              <AlertTriangle size={18} />
              <div><strong>Contracts not deployed yet</strong><p>Run the deployment script, then replace contracts/deployments.json. This app will update without code changes.</p></div>
            </div>
          )}
          {!walletConnectConfigured && (
            <div className="notice warning">
              <AlertTriangle size={18} />
              <div>
                <strong>WalletConnect project ID required</strong>
                <p>Replace the placeholder in web/.env.local, then restart the development server.</p>
              </div>
            </div>
          )}
          {wrongChain && (
            <div className="notice warning">
              <AlertTriangle size={18} /><div><strong>Switch to Monad</strong><p>Chain ID 143 is required to read and execute this combo.</p></div>
            </div>
          )}
          {routerNotAllowed && (
            <div className="notice warning">
              <AlertTriangle size={18} />
              <div>
                <strong>Uniswap router setup required</strong>
                <p>The Registry owner must allowlist Knot&apos;s fixed Uniswap router.</p>
              </div>
            </div>
          )}
          <div className="summary-list">
            <div><span>Premium</span><strong>{formatUsdc(premium)} USDC</strong></div>
            {automaticFunding > premium && (
              <div><span>Repayment funding</span><strong>{formatUsdc(automaticFunding)} USDC</strong></div>
            )}
            <div><span>Wallet balance</span><strong>{formatUsdc(walletBalanceRead.data)} USDC</strong></div>
            <div><span>Expected net USDC</span><strong className={expectedDelta < 0n ? "negative" : "positive"}>{expectedDelta > 0n ? "+" : ""}{formatUsdc(expectedDelta)} USDC</strong></div>
          </div>
          <div className="divider" />
          <div className="simulation">
            <div className="simulation-title"><span>Preflight simulation</span>{simulation.isFetching && <LoaderCircle className="spin" size={16} />}</div>
            {swapQuotePending ? (
              <div className="sim-state neutral"><LoaderCircle className="spin" size={16} /> Fetching Uniswap quote…</div>
            ) : swapQuoteError ? (
              <div className="sim-state error">
                <AlertTriangle size={16} />
                Swap {swapQuoteError.index + 1}: {swapQuoteError.quote?.message}
              </div>
            ) : intermediateShortfall ? (
              <div className="sim-state error">
                <AlertTriangle size={16} />
                Cube {intermediateShortfall.actionIndex + 1} needs {formatUsdc(intermediateShortfall.required)} {intermediateShortfall.asset}, but only {formatUsdc(intermediateShortfall.available)} is guaranteed
              </div>
            ) : insufficientWalletFunds ? (
              <div className="sim-state error">
                <AlertTriangle size={16} />
                Wallet needs {formatUsdc(approvalAmount - (walletBalanceRead.data ?? 0n))} more USDC
              </div>
            ) : needsApproval && approvalAmount > 0n ? (
              <div className="sim-state neutral"><LockKeyhole size={16} /> Exact approval required before simulation</div>
            ) : routerNotAllowed ? (
              <div className="sim-state error"><AlertTriangle size={16} /> Uniswap router is not allowlisted</div>
            ) : simulation.isSuccess ? (
              <div className="sim-state success"><Check size={16} /> Simulation passed</div>
            ) : simulationMessage ? (
              <div className="sim-state error"><AlertTriangle size={16} /> {simulationMessage}</div>
            ) : (
              <div className="sim-state neutral">Complete inputs and connect a wallet to simulate.</div>
            )}
          </div>

          {flowError && <p className="flow-error">{flowError}</p>}
          {receipt.isSuccess ? (
            <a className="primary-action confirmed" href={`https://monadscan.com/tx/${transactionHash}`} target="_blank" rel="noreferrer">
              <Check size={18} /> Confirmed on Monad <ExternalLink size={15} />
            </a>
          ) : transactionHash ? (
            <a className="primary-action pending" href={`https://monadscan.com/tx/${transactionHash}`} target="_blank" rel="noreferrer">
              <LoaderCircle className="spin" size={18} /> Pending confirmation <ExternalLink size={15} />
            </a>
          ) : !isConnected ? (
            <button
              className="primary-action"
              onClick={() => walletConnectConfigured && open()}
              disabled={!walletConnectConfigured}
            >
              {walletConnectConfigured ? "Connect wallet" : "Wallet setup required"}
            </button>
          ) : !swapQuotePending && !swapQuoteError && !intermediateShortfall && needsApproval && approvalAmount > 0n ? (
            <button className="primary-action" onClick={approveExact} disabled={phase !== "idle" || !deployed || wrongChain || insufficientWalletFunds}>
              {phase === "approving" ? <LoaderCircle className="spin" size={18} /> : <LockKeyhole size={18} />}
              Approve exactly {formatUsdc(approvalAmount)} USDC
            </button>
          ) : (
            <button className="primary-action" onClick={sendCombo} disabled={!ready || phase !== "idle"}>
              {phase === "sending" ? <LoaderCircle className="spin" size={18} /> : <Zap size={18} />}
              {ready ? "Send combo" : "Simulation required"}
            </button>
          )}
          {isConnected && needsApproval && approvalAmount > 0n && (
            <p className="approval-copy">Only the exact amount shown is approved—never unlimited.</p>
          )}
        </aside>
          </div>
        </section>
      </div>
    </main>
  );
}

function ActionCube({
  action,
  index,
  swapQuote,
  onChange,
  onRemove,
}: {
  action: CubeInstance;
  index: number;
  swapQuote?: SwapQuoteState;
  onChange: (action: CubeInstance) => void;
  onRemove: () => void;
}) {
  const manifest = cubesById[action.cubeId];
  return (
    <article className="cube action-cube">
      <div className="cube-index action">{index + 1}</div>
      <div className="cube-body">
        <div className="cube-title-row">
          <div className="action-heading"><span className="action-icon">{manifest.icon}</span><div><span className="pin-label">ACTION {index + 1}</span><h2>{manifest.name}</h2></div></div>
          <div className="action-tools">
            {action.cubeId === "swap" && <span className="protocol">Uniswap v3</span>}
            <button className="remove" onClick={onRemove} aria-label={`Remove ${manifest.name}`}><Trash2 size={16} /></button>
          </div>
        </div>
        <div className="field-grid">
          {manifest.inputs.map((field) => {
            const isAmount = field.kind === "amount";
            return (
              <label key={field.key} className={field.kind === "bytes" || field.kind === "address" ? "wide" : ""}>
                <span className="field-label">{field.label}</span>
                {field.kind === "select" ? (
                  <select value={action.inputs[field.key] ?? field.options?.[0]?.value} onChange={(event) => onChange({ ...action, inputs: { ...action.inputs, [field.key]: event.target.value } })}>
                    {field.options?.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                  </select>
                ) : (
                  <div className="compact-input">
                    <input
                      value={action.inputs[field.key] ?? ""}
                      placeholder={isAmount && action.chained ? "Previous output" : field.placeholder}
                      disabled={isAmount && action.chained}
                      inputMode={field.kind === "amount" || field.kind === "percent" ? "decimal" : "text"}
                      onChange={(event) => onChange({ ...action, inputs: { ...action.inputs, [field.key]: event.target.value } })}
                    />
                    {field.kind === "percent" && <span>%</span>}
                  </div>
                )}
                {isAmount && field.allowChained && (
                  <button
                    className={`chain-toggle ${action.chained ? "active" : ""}`}
                    onClick={(event) => {
                      event.preventDefault();
                      onChange({ ...action, chained: !action.chained });
                    }}
                  >
                    <span className="toggle-knob" /> 100% of previous output
                  </button>
                )}
              </label>
            );
          })}
        </div>
        {action.cubeId === "swap" && (
          <div className={`quote-line ${swapQuote?.status ?? "loading"}`}>
            <span>Estimated output</span>
            <strong>
              {swapQuote?.status === "ready"
                ? `${formatTokenAmount(swapQuote.amountOut!, getAddress(action.inputs.tokenOut))} ${tokenSymbol(getAddress(action.inputs.tokenOut))}`
                : swapQuote?.status === "error"
                  ? swapQuote.message || "Unavailable"
                  : "Quoting…"}
            </strong>
          </div>
        )}
      </div>
    </article>
  );
}
