# 0xB Smart Contract

## Project Guides

### Smart Contract (solidity)

The smart contract code is divided into 2 parts:

- `contracts/ZeroXBlock.sol`: Main functionalities, contains all ABI methods to interact.
  Most non-heavy features are written here (transferring, toggling auto-swap, blacklisting, ...)

- `contracts/dependencies/CONTRewardManagement.sol`: Take care of conts storage and reward
  calculation.

### Deployments (typescript)

- `deployments/migrations/001_deploy_cont_management.ts`
- `deployments/migrations/002_deploy_0xB.ts`

### Unit test

- `test/0xB.spec.ts`

## Dev Guides

### Pre-reqs

- Yarn >= v1.22.15
- Node.js >= v12.22.6

### Installation

```sh
cp .env.example .env
```

Then, proceed with installing dependencies:

```sh
yarn install
```

### Compilations

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

### TypeChain

Compile the smart contracts and generate TypeChain artifacts:

```sh
$ yarn typechain
```

### Linting

Lint the Solidity code:

```sh
$ yarn lint:sol
```

Lint the TypeScript code:

```sh
$ yarn lint:ts
```

### Testing

Run the Mocha tests:

```sh
$ yarn test
```

### Coverage

Generate the code coverage report:

```sh
$ yarn coverage
```

### Gas Report

See the gas usage per unit test and average gas per method call:

```sh
$ REPORT_GAS=true yarn test
```

### Cleaning

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```sh
$ yarn clean
```

### Deployment

At the moment, testnet deployment is available on Avalanche Fuji Testnet:

```sh
$ yarn hardhat --network fuji deploy
```

Verify code and display functions on testnet UI:

```sh
yarn hardhat etherscan-verify --api-key <your-api-key> --network fuji --license MIT
```

The API keys can be found on API-KEYS on snowtrace.io account settings. Create an account
on snowtrace, then create an API there.
