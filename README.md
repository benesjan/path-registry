# path-registry
The goal of this project is to make optimal swap paths available in smart contracts without compromising
on trustlessness.

The main smart contract, called ***PathRegistry.sol***, has 2 functions:
1. A registration and a quality verification of Uniswap v2 and v3 paths.
2. Swapping tokens using the registered path.
A path is selected based on input and output token addresses and the amount of input token to swap.

## Setup
1. [Install Foundry](https://github.com/gakonst/foundry#installation)
2. `git clone https://github.com/benesjan/path-registry.git`
3. `git submodule update --init`
4. `cp ./foundry.toml_template ./foundry.toml`
5. Replace ***ARCHIVE_NODE_RPC_URL*** with actual archive node RPC endpoint (Archive node is required for tests to pass becase tests are fixed at a block.)
6. `yarn`
7. `forge build`
8. `forge test`

> Note: Archive node is required for tests to pass because they are fixed at block ***14411926***.
> I use [archivenode.io](https://archivenode.io/) endpoint.