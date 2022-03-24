import { chainIds } from "../hardhat.config";

export const ADDRESSES_FOR_CHAIN_ID: { [key: number]: { WAVAX?: string; JoeRouter?: string } } = {
  [chainIds.fuji]: {
    WAVAX: "0xd00ae08403B9bbb9124bB305C09058E32C39A48c",
    JoeRouter: "0x5db0735cf88f85e78ed742215090c465979b5006",
  },
};
