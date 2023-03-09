# NullController

## Summary
NullController is a Managed Pool Controller that has no ability to issue commands to the Managed Pool. The NullController exists to be a bare minimum framework on top of which other controllers can be built. NullControllerFactory demonstrates a factory that can deploy both a Managed Pool and a controller that are both aware of each other without using a separate `initialize()` function.

## Managed Pool Functions

The following list is a list of permissioned functions in a Managed Pool that a controller could potentially call. Only the checked boxes are functions that _this_ controller is able to call:

- Gradual Updates
	- [x] `pool.updateSwapFeeGradually(...)`
	- [ ] `pool.updateWeightsGradually(...)`
- Enable/Disable Interactions
	- [ ] `pool.setSwapEnabled(...)`
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
