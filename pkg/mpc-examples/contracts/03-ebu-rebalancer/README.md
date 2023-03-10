# EBU Rebalancer Controller

## Summary
EBURebalancer is a Managed Pool Controller that has the ability to pause swaps as well as promote rebalancing through the gradual lowering of swap fees. 

## Details
The EBURebalancer is an extension of the NullController with added ability to rebalance the Managed Pool by enabling swaps, and updating swap fees gradually to a nominal value over the course of 7 days. This lowering of swap fees incentivises arbitrageurs to bring the pool back to its desired weight of 33/33/33.  

## Access Control
### EBURebalancer
The controller has no access control and all callable functions can be executed by any account. There are constraints within the `rebalance()` function, as it can only be called once every `30 days`. The rebalance period is set for `7 days`. During this time period the ability to call `pausePool()` is locked. 

### EBURebalancerFactory
The factory has one permissioned function: `disable()`. Using OZ's Ownable, the factory restricts permission to only the contract `owner`. Ownable was chosen as it is a very simple concept that requires little explanation; however, it may be desirable to grant this permission to more than a single `owner`. Using a solution such as Balancer's [SingletonAuthentication](https://github.com/balancer/balancer-v2-monorepo/blob/3e99500640449585e8da20d50687376bcf70462f/pkg/solidity-utils/contracts/helpers/SingletonAuthentication.sol) could be a useful system for many controller factories.

## Managed Pool Functions
The following list is a list of permissioned functions in a Managed Pool that a controller could potentially call. The EBURebalancer can call the functions below that are denoted with a checked box:

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
