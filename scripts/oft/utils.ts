import chains from "./oftChains.json";

export function getChainByEid(eid: number) {
  const c = chains.filter((c) => (c.eid as number) === eid)[0];
  if (!c) throw new Error("Chain not found");
  return c;
}
