import chains from "./oftChains.json";

export function getChainByEid(eid: number) {
  const c = chains.filter((c) => (c.eid as number) === eid)[0];
  if (!c) throw new Error("Chain not found");
  return c;
}
export function getChainByNetworkName(network: string) {
  const c = chains.filter((c) => c.network === network)[0];
  if (!c) throw new Error("Chain not found");
  return c;
}

export function padAddress(address: string) {
  const strippedAddress = address.replace(/^0x/, "");
  const paddedAddress =
    "0".repeat(64 - strippedAddress.length) + strippedAddress;
  return `0x${paddedAddress}`;
}
