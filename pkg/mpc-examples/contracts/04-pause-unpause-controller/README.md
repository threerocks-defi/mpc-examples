# PauseUnpauseController

## Summary
PauseUnpauseController is a Managed Pool Controller that has the ability to enable & disable swaps of a managed pool. The PauseUnpauseController exists to work as a mental model for how enabling & disabling swaps of a managed pool can work. PauseUnpauseControllerFactory demonstrates a factory that can deploy both a Managed Pool and a controller that are both aware of each other without using a separate `initialize()` function.

## Details
The PauseUnpauseController has two functionalities. It can enable and disable the ability to swap in a managed pool. The enable swaps feature is expected to be used once swapping of a managed pool has been paused and should be enabled again. The two possible ways to unpause the pool are:

- unsafe unpause (no gradualSwapFeePercentage change)
- safe unpause (gradualSwapFeePercentage change)

The safe unpause mechanism can be used to mitigate arbitrage losses occuring if pool swaps are enabled and the market has moved since the pool was paused. Increasing the swapFeePercentage during the safe unpause ensures that arbitrage opportunities are captured by the LPs of the managed pool via swap fees.

## Access Control

### PauseUnpauseController
The PauseUnpause controller uses OZ's Ownable. This allows the pausing & unpausing of the managed pool to only be done as the owner of the PauseUnpauseController

### PauseUnpauseControllerFactory
The factory has one permissioned function: `disable()`. Using OZ's Ownable, the factory restricts permission to only the contract `owner`. Ownable was chosen as it is a very simple concept that requires little explanation; however, it may be desirable to grant this permission to more than a single `owner`. Using a solution such as Balancer's [SingletonAuthentication](https://github.com/balancer/balancer-v2-monorepo/blob/3e99500640449585e8da20d50687376bcf70462f/pkg/solidity-utils/contracts/helpers/SingletonAuthentication.sol) could be a useful system for many controller factories.

## Managed Pool Functions
The following list is a list of permissioned functions in a Managed Pool that a controller could potentially call. The PauseUnpauseController can call the functions below that are denoted with a checked box:

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
