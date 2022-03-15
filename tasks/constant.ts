import { chainIds } from "../hardhat.config";

export const ADDRESSES_FOR_CHAIN_ID: { [key: number]: { WAVAX?: string; JoeRouter?: string } } = {
  [chainIds.fuji]: {
    WAVAX: "0xd00ae08403B9bbb9124bB305C09058E32C39A48c",
    JoeRouter: "0x5db0735cf88f85e78ed742215090c465979b5006",
  },
  [chainIds.rinkeby]: {
    WAVAX: "0xc778417e063141139fce010982780140aa0cd5ab",
    JoeRouter: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
  },
};
