# 0xB Smart Contract

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

At the moment, deployment is available on Avalanche Fuji Testnet:

```sh
$ git stash pop
$ yarn hardhat --network fuji deploy
```

```sh
$ yarn hardhat etherscan-verify --api-key 9N3X4BWMBQI9F7N7GQ96V9QIWK9GR3KEYG --network fuji --license MIT
```
