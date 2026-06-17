import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";

export type Env = "mainnet" | "testnet";

export interface UlnConfigInput {
  confirmations: number;
  requiredDVNs: string[]; // dvn keys (e.g. "layerzero")
  optionalDVNs: string[]; // dvn keys
  optionalDVNThreshold: number;
}

export interface TransferLimitInput {
  dstEid: number;
  maxDailyTransferAmount: string;
  singleTransferUpperLimit: string;
  singleTransferLowerLimit: string;
  dailyTransferAmountPerAddress: string;
  dailyTransferAttemptPerAddress: number;
}

export interface ChainConfig {
  network: string;
  eid: number;
  contract: "ListaOFTAdapterV2" | "ListaOFTv2";
  lzEndpoint: string;
  sendLib: string;
  receiveLib: string;
  executor: string;
  existingTokenAddress?: string;
  tokenName?: string;
  symbol?: string;
  proxy: string;
  dvns: Record<string, string>;
  ulnConfig: UlnConfigInput;
  transferLimits: TransferLimitInput[];
}

// LayerZero V2 config type ids
export const CONFIG_TYPE_EXECUTOR = 1;
export const CONFIG_TYPE_ULN = 2;

/**
 * Resolve the path to the live chains config for the given environment. Falls
 * back to the committed `.example.json` so the scripts can be inspected without
 * a live config present.
 */
export function chainsConfigPath(env: Env): string {
  const dir = __dirname;
  const live = path.join(dir, `oftChainsV2.${env}.json`);
  if (fs.existsSync(live)) return live;
  return path.join(dir, `oftChainsV2.${env}.example.json`);
}

export function loadChains(env: Env): ChainConfig[] {
  const p = chainsConfigPath(env);
  return JSON.parse(fs.readFileSync(p, "utf-8")) as ChainConfig[];
}

export function saveChains(env: Env, chains: ChainConfig[]): void {
  const live = path.join(__dirname, `oftChainsV2.${env}.json`);
  fs.writeFileSync(live, JSON.stringify(chains, null, 2));
}

export function getChainByNetwork(env: Env, network: string): ChainConfig {
  const c = loadChains(env).filter((x) => x.network === network)[0];
  if (!c) throw new Error(`Chain not found for network ${network} (${env})`);
  return c;
}

export function getChainByEid(env: Env, eid: number): ChainConfig {
  const c = loadChains(env).filter((x) => x.eid === eid)[0];
  if (!c) throw new Error(`Chain not found for eid ${eid} (${env})`);
  return c;
}

/** Returns { admin, manager, pauser } from the environment. */
export function getRoles(): { admin: string; manager: string; pauser: string } {
  const admin = process.env.ADMIN || "";
  const manager = process.env.MANAGER || "";
  const pauser = process.env.PAUSER || "";
  if (!ethers.isAddress(admin)) throw new Error("ADMIN env is not a valid address");
  if (!ethers.isAddress(manager)) throw new Error("MANAGER env is not a valid address");
  if (!ethers.isAddress(pauser)) throw new Error("PAUSER env is not a valid address");
  return { admin, manager, pauser };
}

/** left-pads an EVM address to a bytes32 peer representation. */
export function padAddress(address: string): string {
  const stripped = address.replace(/^0x/, "");
  return `0x${"0".repeat(64 - stripped.length)}${stripped}`;
}

/** Maps the tuple shape expected by the contracts' TransferLimit struct. */
export function toTransferLimitTuple(l: TransferLimitInput) {
  return [
    l.dstEid,
    l.maxDailyTransferAmount,
    l.singleTransferUpperLimit,
    l.singleTransferLowerLimit,
    l.dailyTransferAmountPerAddress,
    l.dailyTransferAttemptPerAddress,
  ];
}

/** Resolves DVN keys to addresses, sorted ascending + deduped (ULN requirement). */
function resolveDVNs(cfg: ChainConfig, keys: string[]): string[] {
  const addrs = keys.map((k) => {
    const a = cfg.dvns[k];
    if (!a) throw new Error(`DVN "${k}" not found in chain ${cfg.network}`);
    return ethers.getAddress(a);
  });
  const unique = Array.from(new Set(addrs));
  return unique.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
}

/**
 * ABI-encodes a UlnConfig:
 *   struct UlnConfig {
 *     uint64 confirmations;
 *     uint8  requiredDVNCount;
 *     uint8  optionalDVNCount;
 *     uint8  optionalDVNThreshold;
 *     address[] requiredDVNs;   // sorted ascending
 *     address[] optionalDVNs;   // sorted ascending
 *   }
 */
export function encodeUlnConfig(cfg: ChainConfig): string {
  const required = resolveDVNs(cfg, cfg.ulnConfig.requiredDVNs);
  const optional = resolveDVNs(cfg, cfg.ulnConfig.optionalDVNs);
  const uln = {
    confirmations: cfg.ulnConfig.confirmations,
    requiredDVNCount: required.length,
    optionalDVNCount: optional.length,
    optionalDVNThreshold: cfg.ulnConfig.optionalDVNThreshold,
    requiredDVNs: required,
    optionalDVNs: optional,
  };
  return ethers.AbiCoder.defaultAbiCoder().encode(
    [
      "tuple(uint64 confirmations,uint8 requiredDVNCount,uint8 optionalDVNCount,uint8 optionalDVNThreshold,address[] requiredDVNs,address[] optionalDVNs)",
    ],
    [uln]
  );
}

/**
 * ABI-encodes an ExecutorConfig:
 *   struct ExecutorConfig { uint32 maxMessageSize; address executor; }
 */
export function encodeExecutorConfig(cfg: ChainConfig, maxMessageSize = 10000): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ["tuple(uint32 maxMessageSize,address executor)"],
    [{ maxMessageSize, executor: ethers.getAddress(cfg.executor) }]
  );
}

/** Minimal LayerZero V2 EndpointV2 ABI for library + config wiring. */
export const ENDPOINT_ABI = [
  "function setSendLibrary(address oapp, uint32 eid, address newLib) external",
  "function setReceiveLibrary(address oapp, uint32 eid, address newLib, uint256 gracePeriod) external",
  "function setConfig(address oapp, address lib, tuple(uint32 eid, uint32 configType, bytes config)[] params) external",
];
