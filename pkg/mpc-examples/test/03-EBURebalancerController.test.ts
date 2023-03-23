import { assert, expect } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';
import * as time from '@orbcollective/shared-dependencies/time';
import { setupEnvironment, TokenList, pickTokenAddresses } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress;
let rando: SignerWithAddress;
let mpcFactory: Contract;
let ebuRebalancerController: Contract;
let tokenAddresses: string[];

const initialWeights = toNormalizedWeights([fp(33.34), fp(33.33), fp(33.33)]);
const minSwapFeePercentage = bn(1e12); // 0.0001%

async function deployBalancerContract(
  task: string,
  contractName: string,
  deployer: SignerWithAddress,
  args: unknown[]
): Promise<Contract> {
  const artifact = await getBalancerContractArtifact(task, contractName);
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, deployer);
  const contract = await factory.deploy(...args);
  return contract;
}

async function deployController(deployer: SignerWithAddress): Promise<Contract> {
  const newPoolParams = {
    name: 'MyTestPool',
    symbol: 'MTP',
    tokens: tokenAddresses,
    normalizedWeights: initialWeights,
    // assetManagers: [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS],
    minSwapFeePercentage: minSwapFeePercentage,
    // swapEnabledOnStart: false,
    // mustAllowlistLPs: false,
    managementAumFeePercentage: fp(0.1),
    aumFeeId: 0,
  };

  const receipt = await (await mpcFactory.connect(deployer).create(newPoolParams)).wait();
  const eventController = expectEvent.inReceipt(receipt, 'ControllerCreated');

  return ethers.getContractAt('EBURebalancerController', eventController.args.controller);
}

async function fastForward(sec: number) {
  const mostRecentBlock = await ethers.provider.getBlockNumber();
  const timestamp = (await ethers.provider.getBlock(mostRecentBlock)).timestamp;
  await ethers.provider.send('evm_mine', [timestamp + sec]);
}

async function deployBalancerManagedPoolFactory(
  task: string,
  libNames: string[],
  contractName: string,
  deployer: SignerWithAddress,
  args: unknown[]
): Promise<Contract> {
  const lib_cb = await deployBalancerContract(task, libNames[0], deployer, []);
  const lib_art = await deployBalancerContract(task, libNames[1], deployer, []);
  const libraries = {
    CircuitBreakerLib: lib_cb.address,
    ManagedPoolAddRemoveTokenLib: lib_art.address,
  };

  const artifact = await getBalancerContractArtifact(task, contractName);
  const factory = await ethers.getContractFactoryFromArtifact(artifact, { signer: deployer, libraries });
  const instance = await factory.deploy(...args);
  return instance.deployed();
}

async function deployLocalContract(contract: string, deployer: SignerWithAddress, args: unknown[]): Promise<Contract> {
  const Controller = await ethers.getContractFactory(contract);
  const c = await Controller.connect(deployer).deploy(...args);
  const instance: Contract = await c.deployed();
  return instance;
}

describe('EBURebalancerController', () => {
  let vault: Contract;
  let tokens: TokenList;

  before('Setup', async () => {
    let trader: SignerWithAddress;
    ({ vault, tokens, deployer, trader } = await setupEnvironment());
    rando = trader;

    const pfpArgs = [vault.address, fp(0.1), fp(0.1)];
    const protocolFeesProvider = await deployBalancerContract(
      '20220725-protocol-fee-percentages-provider/',
      'ProtocolFeePercentagesProvider',
      deployer,
      pfpArgs
    );

    tokenAddresses = pickTokenAddresses(tokens, 3);

    const factoryTask = 'deprecated/20221021-managed-pool';
    const libNames = ['CircuitBreakerLib', 'ManagedPoolAddRemoveTokenLib'];
    const factoryContract = 'ManagedPoolFactory';
    const poolFactoryArgs = [vault.address, protocolFeesProvider.address];
    const mpFactory = await deployBalancerManagedPoolFactory(
      factoryTask,
      libNames,
      factoryContract,
      deployer,
      poolFactoryArgs
    );

    const controllerFactoryArgs = [vault.address, mpFactory.address];
    mpcFactory = await deployLocalContract('EBURebalancerControllerFactory', deployer, controllerFactoryArgs);
  });

  describe('Controller Deployment', () => {
    beforeEach('deploy', async () => {
      ebuRebalancerController = await deployController(deployer);
    });

    it("Local Controller's Vault is the Vault", async () => {
      assert.equal(vault.address, await ebuRebalancerController.getVault());
    });

    it('Deploys managed pool; controller set as AM for all tokens', async () => {
      const poolId = await ebuRebalancerController.getPoolId();
      const tokens = await ebuRebalancerController.getPoolTokens();

      for (let i = 0; i < tokens.length; i++) {
        const info = await vault.getPoolTokenInfo(poolId, tokens[i]);
        assert.equal(info.assetManager, ebuRebalancerController.address);
      }
    });
  });

  describe('Rebalance Pool', () => {
    beforeEach('Deploy controller and call rebalance', async () => {
      ebuRebalancerController = await deployController(deployer);
      await ebuRebalancerController.rebalancePool();
    });

    it('pause swaps successfully', async () => {
      // fast-forward time 7 days and pause swaps
      await fastForward(time.WEEK);
      await ebuRebalancerController.pausePool();

      assert.equal(await ebuRebalancerController.isPoolPaused(), true);
    });

    it('Fail to pause swaps during rebalancing', async () => {
      await expect(ebuRebalancerController.pausePool()).to.be.revertedWith('Pool is still rebalancing');
    });

    it('Fail to call rebalance, until the 30th day in which the call will be successful', async () => {
      const intervals = 5;
      const timePerStep = time.MONTH / intervals;

      for (let i = 1; i <= intervals; i++) {
        await fastForward(timePerStep);
        if (i != intervals) {
          await expect(ebuRebalancerController.rebalancePool()).to.be.revertedWith(
            'Minimum time between calls not met'
          );
        } else {
          const receipt = await (await ebuRebalancerController.rebalancePool()).wait();
          await expectEvent.inReceipt(receipt, 'PoolRebalancing');
        }
      }
    });

    it('successfully pause swaps then rebalance', async () => {
      await fastForward(time.MONTH);
      await ebuRebalancerController.pausePool();
      const receipt = await (await ebuRebalancerController.rebalancePool()).wait();
      await expectEvent.inReceipt(receipt, 'PoolRebalancing');
    });
  });

  describe('Factory Access Control', () => {
    it('Non-owner cannot disable the factory', async () => {
      await expect(mpcFactory.connect(rando).disable()).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('Owner can disable the factory', async () => {
      await deployController(deployer);
      await mpcFactory.connect(deployer).disable();
      await expect(deployController(deployer)).to.be.revertedWith('Controller factory disabled');
    });
  });
});
