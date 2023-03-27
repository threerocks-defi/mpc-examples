# EBU Rebalancer Controller

## Summary
EbuRebalancerController is a Managed Pool Controller that has the ability to pause swaps as well as promote rebalancing through the gradual lowering of swap fees. 

## Details
The EbuRebalancer is a Managed Pool Controller that makes the pool a nominally static basket of tokens. It allows anyone to rebalance the Managed Pool by using the `rebalancePool` function. The rebalance works by enabling swaps with an extremely high swap fee and gradually ramping down the fees to a nominal (near-zero) value. The gradual swap fee decrease incentivizes arbitrageurs to bring the pool back to its desired weight by progressively creating minimally viable arbitrage opportunities.

## Access Control
### EbuRebalancerController
The controller has no access control and all callable functions can be executed by any account. There are constraints within the `rebalancePool()` function, as it can only be called once every `30 days`. The rebalance period is set for `7 days`. During this time period the ability to call `pausePool()` is locked. 

### EbuRebalancerFactory
The factory has one permissioned function: `disable()`. Using OZ's Ownable, the factory restricts permission to only the contract `owner`. Ownable was chosen as it is a very simple concept that requires little explanation; however, it may be desirable to grant this permission to more than a single `owner`. Using a solution such as Balancer's [SingletonAuthentication](https://github.com/balancer/balancer-v2-monorepo/blob/3e99500640449585e8da20d50687376bcf70462f/pkg/solidity-utils/contracts/helpers/SingletonAuthentication.sol) could be a useful system for many controller factories.

## Managed Pool Functions
The following list is a list of permissioned functions in a Managed Pool that a controller could potentially call. The EBURebalancerController can call the functions below that are denoted with a checked box:

- Gradual Updates
	- [x] `pool.updateSwapFeeGradually(...)`
	- [ ] `pool.updateWeightsGradually(...)`
- Enable/Disable Interactions
	- [x] `pool.setSwapEnabled(...)`
	- [ ] `pool.setJoinExitEnabled(...)`
- LP Allowlist Management
	- [ ] `pool.setMustAllowlistLPs(...)`
	- [ ] `pool.addAllowedAddress(...)`
	- [ ] `pool.removeAllowedAddress(...)`
- Add/Remove Token
	- [ ] `pool.addToken(...)`
	- [ ] `pool.removeToken(...)`
- Circuit Breaker Management
	- [ ] `pool.setCircuitBreakers(...)`
- Management Fee
	- [ ] `pool.setManagementAumFeePercentage(...)`
