# <img src="logo.svg" alt="Balancer" height="128px">

# Managed Pool Controllers Examples

[![CI Status](https://github.com/orbcollective/mpc-examples/workflows/CI/badge.svg)](https://github.com/orbcollective/mpc-examples/actions)
[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](https://www.gnu.org/licenses/gpl-3.0)

This repository contains simplified examples of possible functionality in a Managed Pool Controller. These controllers are provided as examples for informational purposes only and have not been audited.

# Controllers

| Number | Controller      | Description |
| ----------- | ----------- | ----------- |
| 00 | [NullController](./pkg/mpc-examples/contracts/00-null-controller/README.md) | Empty controller that does nothing |
| 01 | [WeightChangerController](./pkg/mpc-examples/contracts/01-weight-changer/README.md) | Controller that allows users to gradually update token weights | 
| 03 | [EbuRebalancerController](./pkg/mpc-examples/contracts/03-ebu-rebalancer/README.md) | Controller that implements a static weighted basket of tokens. Can be rebalanced back to intended weights with a swap fee rebalance. |

## Build and Test

On the project root, run:

```bash
$ yarn # install all dependencies
$ yarn build # compile all contracts
$ yarn test # run all tests
```

## Licensing

Most of the Solidity source code is licensed under the GNU General Public License Version 3 (GPL v3): see [`LICENSE`](./LICENSE).
