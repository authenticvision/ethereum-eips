import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@primitivefi/hardhat-dodoc';

require('hardhat-contract-sizer');

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,
      },
    }
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  },
  gasReporter: {
    enabled: true,
    token: 'ETH',
    coinmarketcap: '<insertYourKeyHere>'
  },
  dodoc: {
    path: './docs',
    debugMode: false,
    runOnCompile: true,
    
  }
};

export default config;
