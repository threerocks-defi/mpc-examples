import { expect } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractAbi, getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';

import { TokenList, setupEnvironment, pickTokenAddresses } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';
import { BigNumber } from 'ethers';

import { actionId } from '@orbcollective/shared-dependencies/test-helpers/actions';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress, rando: SignerWithAddress;
let admin: SignerWithAddress;
let controllerOwner: SignerWithAddress;
let mpcFactory: Contract;
let mpFactory: Contract;
let tokenAddresses: string[];
const endSwapFeePercentage = bn(3e15);

const initialWeights = toNormalizedWeights([fp(30), fp(70)]);
const swapFeePercentage = bn(0.3e16);

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

async function deployController(
  deployer: SignerWithAddress,
  controllerOwner: SignerWithAddress,
  endSwapFeePercentage: BigNumber
): Promise<Contract> {
  const newPoolParams = {
    name: 'MyTestPool',
    symbol: 'MTP',
    tokens: tokenAddresses,
    normalizedWeights: initialWeights,
    // assetManagers: [ZERO_ADDRESS, ZERO_ADDRESS],
    swapFeePercentage: swapFeePercentage,
    swapEnabledOnStart: true,
    // mustAllowlistLPs: false,
    managementAumFeePercentage: fp(0.1),
    aumFeeId: 0,
  };

  const receipt = await (
    await mpcFactory.connect(deployer).create(newPoolParams, controllerOwner.address, endSwapFeePercentage)
  ).wait();
  const eventController = expectEvent.inReceipt(receipt, 'ControllerCreated');

  return ethers.getContractAt('PauseUnpauseController', eventController.args.controller);
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

describe('PauseUnpauseController', function () {
  let vault: Contract;
  let tokens: TokenList;
  before('Setup', async () => {
    let trader: SignerWithAddress;
    let liquidityProvider: SignerWithAddress;
    ({ vault, tokens, deployer, liquidityProvider, trader, admin } = await setupEnvironment());
    rando = trader;
    controllerOwner = liquidityProvider;

    const pfpArgs = [vault.address, fp(0.1), fp(0.1)];
    const protocolFeesProvider = await deployBalancerContract(
      '20220725-protocol-fee-percentages-provider/',
      'ProtocolFeePercentagesProvider',
      deployer,
      pfpArgs
    );

    tokenAddresses = pickTokenAddresses(tokens, 2);

    const factoryTask = 'deprecated/20221021-managed-pool';
    const libNames = ['CircuitBreakerLib', 'ManagedPoolAddRemoveTokenLib'];
    const factoryContract = 'ManagedPoolFactory';
    const poolFactoryArgs = [vault.address, protocolFeesProvider.address];
    mpFactory = await deployBalancerManagedPoolFactory(
      factoryTask,
      libNames,
      factoryContract,
      deployer,
      poolFactoryArgs
    );

    mpcFactory = await deployLocalContract('PauseUnpauseControllerFactory', deployer, [
      vault.address,
      mpFactory.address,
    ]);
  });

  describe('Controller Deployment', () => {
    let localController: Contract;
    let pool: Contract;

    beforeEach('deploy', async () => {
      localController = await deployController(deployer, controllerOwner, endSwapFeePercentage);
      pool = await getManagedPoolContract(localController);
    });

    async function getManagedPoolContract(localController: Contract): Promise<Contract> {
      const poolId = await localController.getPoolId();
      const [poolAddress] = await vault.getPool(poolId);
      const managedPoolAbi = await getBalancerContractAbi('deprecated/20221021-managed-pool', 'ManagedPool');
      const managedPool = new ethers.Contract(poolAddress, managedPoolAbi, deployer);
      return managedPool;
    }

    it('sets the controller address as owner', async () => {
      expect(localController.address).to.equal(await pool.getOwner());
    });

    it("checks if local controller's vault is the vault", async () => {
      expect(await localController.getVault()).to.equal(vault.address);
    });

    it('deploys managed pool; controller set as AM for all tokens', async () => {
      const poolId = await localController.getPoolId();
      for (let index = 0; index < tokenAddresses.length; index++) {
        const element = await vault.getPoolTokenInfo(poolId, tokenAddresses[index]);
        expect(element.assetManager).to.be.equal(localController.address);
      }
    });

    it('checks if controller is from the factory', async () => {
      expect(await mpcFactory.isControllerFromFactory(localController.address)).to.be.true;
    });

    it('ensures controller at ZERO_ADDRESS is not logged in the factory', async () => {
      expect(await mpcFactory.isControllerFromFactory(ZERO_ADDRESS)).to.be.false;
    });

    it('stores the last created pool', async () => {
      expect(await mpcFactory.getLastCreatedPool()).to.equal(pool.address);
    });

    it('sets the _END_SWAP_FEE_PERCENTAGE as gradualSwapFeeUpdateParams', async () => {
      await localController.connect(controllerOwner).pausePool();
      await localController.connect(controllerOwner).safeUnpausePool();

      expect((await pool.getGradualSwapFeeUpdateParams())['endSwapFeePercentage']).to.be.equal(endSwapFeePercentage);
    });

    describe('Controller access control', async () => {
      it('sets the controllerOwner as localControllerOwner', async () => {
        expect(await localController.owner()).to.equal(controllerOwner.address);
      });
      it('allows the controllerOwner to pause the pool', async () => {
        await localController.connect(controllerOwner).pausePool();
        expect(await localController.isPoolPaused()).to.equal(true);
        expect(await pool.getSwapEnabled()).to.equal(false);
      });
      it('disallows rando to pause the pool', async () => {
        await expect(localController.connect(rando).pausePool()).to.be.revertedWith('Ownable: caller is not the owner');
      });
      it('allows the controllerOwner to safely unpause the pool', async () => {
        const swapFeeParamsBefore = await pool.getGradualSwapFeeUpdateParams();
        await localController.connect(controllerOwner).pausePool();
        await localController.connect(controllerOwner).safeUnpausePool();

        expect(await pool.getSwapEnabled()).to.be.true;
        expect(swapFeeParamsBefore === (await pool.getGradualSwapFeeUpdateParams())).to.be.false;
      });

      it('allows the controllerOwner to dangerously unpause the pool', async () => {
        await localController.connect(controllerOwner).pausePool();
        await localController.connect(controllerOwner).dangrousUnpausePool();
        expect(await pool.getSwapEnabled()).to.be.true;
      });
      it('disallows the rando to unpause the pool', async () => {
        await localController.connect(controllerOwner).pausePool();
        await expect(localController.connect(rando).safeUnpausePool()).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
        await expect(localController.connect(rando).dangrousUnpausePool()).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('Factory Access Control', () => {
      it('Non-owner cannot disable the factory', async () => {
        await expect(mpcFactory.connect(rando).disable()).to.be.revertedWith('Ownable: caller is not the owner');
      });

      it('Owner can disable the factory', async () => {
        await deployController(deployer, controllerOwner, endSwapFeePercentage);
        await mpcFactory.connect(deployer).disable();
        expect(await mpcFactory.isDisabled()).to.be.true;
        await expect(deployController(deployer, controllerOwner, endSwapFeePercentage)).to.be.revertedWith(
          'Controller factory is disabled'
        );
      });
    });
  });

  describe('Factory disabled conditional', () => {
    // the Controller Factory is disabled in the previous test
    // the Managed Pool Factory is still active
    // deploy a new localController Factory & deactive
    // the Managed Pool Factory afterwards to test the
    it('checks conditional', async () => {
      const localControllerFactory = await deployLocalContract('PauseUnpauseControllerFactory', deployer, [
        vault.address,
        mpFactory.address,
      ]);

      expect(await localControllerFactory.isDisabled()).to.be.false;
      expect(await mpFactory.isDisabled()).to.be.false;

      // grant admin the role via the authorizer to disable the Managed Pool factory
      const authorizerArtifact = await getBalancerContractArtifact('20210418-authorizer', 'Authorizer');
      const authorizer = await ethers.getContractAt(authorizerArtifact.abi, await vault.getAuthorizer());
      const aId = actionId(mpFactory, 'disable');
      await authorizer.connect(admin).grantRole(aId, admin.address);
      await mpFactory.connect(admin).disable();
      expect(await mpFactory.isDisabled()).to.be.true;
      expect(await localControllerFactory.isDisabled()).to.be.true;
    });
  });
});
