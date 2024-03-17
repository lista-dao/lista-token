import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

declare module "mocha" {
  export interface Context {
    deployer: SignerWithAddress;
    addrs: SignerWithAddress[];
  }
}
