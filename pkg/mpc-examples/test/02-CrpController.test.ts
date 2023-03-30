import { assert, expect } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';

import { TokenList, setupEnvironment, pickTokenAddresses } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress, manager: SignerWithAddress, trader: SignerWithAddress, liquidityProvider: SignerWithAddress;
let mpcFactory: Contract;
let tokenAddresses: string[];

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

async function deployController(deployer: SignerWithAddress, args: unknown[]): Promise<Contract> {
  const newPoolParams = {
    name: 'MyTestPool',
    symbol: 'MTP',
    tokens: tokenAddresses,
    normalizedWeights: initialWeights,
    assetManagers: [ZERO_ADDRESS, ZERO_ADDRESS], // this will be overwritten in the MPC factory
    swapFeePercentage: swapFeePercentage,
    swapEnabledOnStart: true,
    mustAllowlistLPs: false, // this will be overwritten in the MPC factory
    managementAumFeePercentage: fp(0.1),
    aumFeeId: 0,
  };

  const receipt = await (await mpcFactory.connect(deployer).create(newPoolParams, ...args)).wait();
  const eventController = expectEvent.inReceipt(receipt, 'ControllerCreated');

  return ethers.getContractAt('CrpController', eventController.args.controller);
}

async function failTodeployController(deployer: SignerWithAddress, args: unknown[]): Promise<Contract> {
  const newPoolParams = {
    name: 'MyTestPool',
    symbol: 'MTP',
    tokens: tokenAddresses,
    normalizedWeights: initialWeights,
    assetManagers: [ZERO_ADDRESS, ZERO_ADDRESS], // this will be overwritten in the MPC factory
    swapFeePercentage: swapFeePercentage,
    swapEnabledOnStart: true,
    mustAllowlistLPs: false, // this will be overwritten in the MPC factory
    managementAumFeePercentage: fp(0.1),
    aumFeeId: 0,
  };
  expect(await (await mpcFactory.connect(deployer).create(newPoolParams, ...args)).wait()).to.be.revertedWith('CREATE2_DEPLOY_FAILED');
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

enum CrpRight {
  ADD_ALLOWED_ADDRESS,
  ADD_TOKEN,
  REMOVE_ALLOWED_ADDRESS,
  REMOVE_TOKEN,
  SET_CIRCUIT_BREAKERS,
  SET_JOIN_EXIT_ENABLED,
  SET_MANAGEMENT_AUM_FEE_PERCENTAGE,
  SET_MUST_ALLOWLIST_LPS,
  SET_SWAP_ENABLED,
  UPDATE_SWAP_FEE_GRADUALLY,
  UPDATE_WEIGHTS_GRADUALLY,
  LENGTH // Using LENGTH since `type(<Enum>).max;` not implemented until 0.8.8
}

describe.only('CrpController', function () {
  let vault: Contract;
  let tokens: TokenList;
  before('Setup', async () => {
    ({ vault, tokens, deployer, trader, liquidityProvider} = await setupEnvironment());
    manager = trader;
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
    const mpFactory = await deployBalancerManagedPoolFactory(
      factoryTask,
      libNames,
      factoryContract,
      deployer,
      poolFactoryArgs
    );

    const controllerFactoryArgs = [vault.address, mpFactory.address];
    mpcFactory = await deployLocalContract('CrpControllerFactory', deployer, controllerFactoryArgs);
  });

  describe('Validate Controller Deployment', () => {
    let localController: Contract;
    beforeEach('deploy', async () => {
      const rights = [];
      const args = [manager.address, rights];
      localController = await deployController(deployer, args);
    });
    it("Local Controller's Vault is the Vault", async () => {
      assert.equal(vault.address, await localController.getVault());
    });
  });

  describe('Deploy a controller with all rights', () => {
    let localController: Contract;
    it('deploy with all rights', async () => {
      const rights = [CrpRight.ADD_ALLOWED_ADDRESS, CrpRight.ADD_TOKEN, CrpRight.REMOVE_ALLOWED_ADDRESS, CrpRight.REMOVE_TOKEN, CrpRight.SET_CIRCUIT_BREAKERS, CrpRight.SET_JOIN_EXIT_ENABLED, CrpRight.SET_MANAGEMENT_AUM_FEE_PERCENTAGE, CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.SET_SWAP_ENABLED, CrpRight.UPDATE_SWAP_FEE_GRADUALLY, CrpRight.UPDATE_WEIGHTS_GRADUALLY];
      const args = [manager.address, rights];
      localController = await deployController(deployer, args);
      const queriedRights = await localController.getAllRights();

      // make sure that every right we put in comes out as true
      for (var i = 0; i < rights.length; i++) {
        assert(queriedRights[rights[i]]);
      }
    });
    it('Deploy a controller with CrpRight.LENGTH (invalid) as a right', async () => {
      const rights = [CrpRight.ADD_ALLOWED_ADDRESS, CrpRight.ADD_TOKEN, CrpRight.REMOVE_ALLOWED_ADDRESS, CrpRight.REMOVE_TOKEN, CrpRight.SET_CIRCUIT_BREAKERS, CrpRight.SET_JOIN_EXIT_ENABLED, CrpRight.SET_MANAGEMENT_AUM_FEE_PERCENTAGE, CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.SET_SWAP_ENABLED, CrpRight.UPDATE_SWAP_FEE_GRADUALLY, CrpRight.UPDATE_WEIGHTS_GRADUALLY, CrpRight.LENGTH];
      const args = [manager.address, rights];
      failTodeployController(deployer, args);
    });
    it('Deploy a controller with a large enum as a right (>CrpRight.LENGTH)', async () => {
      const rights = [CrpRight.LENGTH + 5];
      const args = [manager.address, rights];
      failTodeployController(deployer, args);
    });
  });

  describe('Add/Remove Rights', () => {
    describe('Controller is only Asset Manager if it has add/remove rights', () => {
      it("No add/remove rights: AM=address(0)", async () => {
        let localController: Contract;
        const rights = [];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);

        const poolId = await localController.getPoolId();
        for (let i = 0; i < tokenAddresses.length; i++) {
          const info = await vault.getPoolTokenInfo(poolId, tokenAddresses[i]);
          assert.equal(info.assetManager, ZERO_ADDRESS);
          assert.notEqual(info.assetManager, localController.address);
        }
      });

      it("Only add rights: AM=controller", async () => {
        let localController: Contract;
        const rights = [CrpRight.ADD_TOKEN];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);

        const poolId = await localController.getPoolId();
        for (let i = 0; i < tokenAddresses.length; i++) {
          const info = await vault.getPoolTokenInfo(poolId, tokenAddresses[i]);
          assert.notEqual(info.assetManager, ZERO_ADDRESS);
          assert.equal(info.assetManager, localController.address);
        }
      });

      it("Only remove rights: AM=controller", async () => {
        let localController: Contract;
        const rights = [CrpRight.REMOVE_TOKEN];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);

        const poolId = await localController.getPoolId();
        for (let i = 0; i < tokenAddresses.length; i++) {
          const info = await vault.getPoolTokenInfo(poolId, tokenAddresses[i]);
          assert.notEqual(info.assetManager, ZERO_ADDRESS);
          assert.equal(info.assetManager, localController.address);
        }
      });

      it("Both add and remove rights: AM=controller", async () => {
        let localController: Contract;
        const rights = [CrpRight.ADD_TOKEN, CrpRight.REMOVE_TOKEN];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);

        const poolId = await localController.getPoolId();
        for (let i = 0; i < tokenAddresses.length; i++) {
          const info = await vault.getPoolTokenInfo(poolId, tokenAddresses[i]);
          assert.notEqual(info.assetManager, ZERO_ADDRESS);
          assert.equal(info.assetManager, localController.address);
        }
      });
    });
  });
  describe('Liquidity Provider Allowlist Validation (setMustAllowlistLPs = true)', () => {
    describe("addAllowedAddress = false, removeAllowedAddress = false", async () => {
      let localController: Contract;
      before('deploy controller', async () => {
        const rights = [CrpRight.SET_MUST_ALLOWLIST_LPS];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);
      });
      it("Fail to add allowed address", async () => {
        expect(localController.connect(manager).addAllowedAddress(manager.address)).to.be.revertedWith('Right not granted');
      });
      it("Fail to remove allowed address", async () => {
        expect(localController.connect(manager).removeAllowedAddress(manager.address)).to.be.revertedWith('Right not granted');
      });
    });
    describe("addAllowedAddress = true, removeAllowedAddress = false", async () => {
      let localController: Contract;
      before('deploy controller', async () => {
        const rights = [CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.ADD_ALLOWED_ADDRESS];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);
      });
      it("Able to add allowed address", async () => {
        await localController.connect(manager).addAllowedAddress(manager.address);
      });
      it("Fail to remove allowed address", async () => {
        expect(localController.connect(manager).removeAllowedAddress(manager.address)).to.be.revertedWith('Right not granted');
      });
    });
    describe("addAllowedAddress = true, removeAllowedAddress = true", async () => {
      let localController: Contract;
      before('deploy controller', async () => {
        const rights = [CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.ADD_ALLOWED_ADDRESS, CrpRight.REMOVE_ALLOWED_ADDRESS];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);
      });
      it("Able to add allowed address", async () => {
        await localController.connect(manager).addAllowedAddress(manager.address);
      });
      it("Able to remove allowed address", async () => {
        await localController.connect(manager).removeAllowedAddress(manager.address);
      });
    });
    describe("addAllowedAddress = false, removeAllowedAddress = true", async () => {
      let localController: Contract;
      before('deploy controller', async () => {
        const rights = [CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.REMOVE_ALLOWED_ADDRESS];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);
      });
      it("Fail to add allowed address", async () => {
        expect(localController.connect(manager).addAllowedAddress(manager.address)).to.be.revertedWith('Right not granted');
      });
      it("Controller attempts to remove address, fails at pool b/c add failed", async () => {
        expect(localController.connect(manager).removeAllowedAddress(manager.address)).to.be.revertedWith('BAL#433');
      });
    });
    describe("addAllowedAddress = true, removeAllowedAddress = true, but renounce addAllowedAddress after add", async () => {
      let localController: Contract;
      before('deploy controller', async () => {
        const rights = [CrpRight.SET_MUST_ALLOWLIST_LPS, CrpRight.ADD_ALLOWED_ADDRESS, CrpRight.REMOVE_ALLOWED_ADDRESS];
        const args = [manager.address, rights];
        localController = await deployController(deployer, args);
      });
      it("Able to add allowed address", async () => {
        await localController.connect(manager).addAllowedAddress(manager.address);
      });
      it("Renounce ADD_ALLOWED_ADDRESS", async () => {
        await localController.connect(manager).renounceRight(CrpRight.ADD_ALLOWED_ADDRESS);
      });
      it("Able to remove allowed address", async () => {
        await localController.connect(manager).removeAllowedAddress(manager.address);
      });
    });
  });
});
