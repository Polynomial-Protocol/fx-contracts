import commonConfig from '@polynomial/common-config/hardhat.config';

import 'solidity-docgen';
import { templates } from '@polynomial/docgen';

const config = {
  ...commonConfig,
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
};

export default config;
