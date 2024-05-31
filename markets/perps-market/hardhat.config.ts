import commonConfig from '@polynomial/common-config/hardhat.config';

import 'solidity-docgen';
import { templates } from '@polynomial/docgen';

const config = {
  ...commonConfig,
  allowUnlimitedContractSize: true,
  docgen: {
    exclude: [
      './interfaces/external',
      './modules',
      './mixins',
      './mocks',
      './utils',
      './storage',
      './Proxy.sol',
      './Router.sol',
    ],
    templates,
  },
  mocha: {
    timeout: 30_000,
  },
};

export default config;
