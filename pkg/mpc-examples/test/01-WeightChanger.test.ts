import { assert } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';
import * as time from '@orbcollective/shared-dependencies/time';
import { pickTokenAddresses, setupEnvironment, TokenList } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';
import { BigNumber } from 'ethers';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress;
let mpcFactory: Contract;
let weightChanger: Contract;
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

async function deployController(deployer: SignerWithAddress): Promise<Contract> {
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

  const receipt = await (await mpcFactory.connect(deployer).create(newPoolParams)).wait();
  const eventController = expectEvent.inReceipt(receipt, 'ControllerCreated');

  return ethers.getContractAt('WeightChanger', eventController.args.controller);
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

describe('WeightChanger', () => {
  let vault: Contract;
  let tokens: TokenList;

  before('Setup', async () => {
    ({ vault, tokens, deployer } = await setupEnvironment());

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
    mpcFactory = await deployLocalContract('WeightChangerFactory', deployer, controllerFactoryArgs);
  });

  describe('Controller Deployment', () => {
    beforeEach('deploy', async () => {
      weightChanger = await deployController(deployer);
    });

    it("Local Controller's Vault is the Vault", async () => {
      assert.equal(vault.address, await weightChanger.getVault());
    });

    it('Deploys managed pool; controller set as AM for all tokens', async () => {
      const poolId = await weightChanger.getPoolId();
      const tokens = await weightChanger.getPoolTokens();

      // Start index at 1 to skip BPT
      for (let i = 1; i < tokens.length; i++) {
        const info = await vault.getPoolTokenInfo(poolId, tokens[i]);
        assert.equal(info.assetManager, weightChanger.address);
      }
    });

    it('Initial weights are set 30/70', async () => {
      assert.isTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), initialWeights));
    });

    it('Reweight duration set at 7 days', async () => {
      assert.equal(await weightChanger.getReweightDuration(), time.WEEK);
    });
  });

  // All weights are in terms of WETH/USDC
  describe('Change Managed Pool weights', () => {
    context('Change weights to 50/50', () => {
      let desiredWeights: BigNumber[];
      beforeEach('call make5050 function', async () => {
        desiredWeights = toNormalizedWeights([fp(50), fp(50)]);
        weightChanger = await deployController(deployer);
        await weightChanger.make5050();
      });

      it('Failure after 4 days', async () => {
        await fastForward(time.DAY * 4);
        assert.isNotTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });

      it('Successful after 8 days', async () => {
        await fastForward(time.DAY * 8);
        assert.isTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });
    });

    context('Change weights to 80/20', () => {
      let desiredWeights: BigNumber[];
      beforeEach('call make8020 function', async () => {
        desiredWeights = toNormalizedWeights([fp(80), fp(20)]);
        weightChanger = await deployController(deployer);
        await weightChanger.make8020();
      });

      it('Failure after 4 days', async () => {
        await fastForward(time.DAY * 4);
        assert.isNotTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });

      it('Successful after 8 days', async () => {
        await fastForward(time.DAY * 8);
        assert.isTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });
    });

    context('Change weights to 99/01', () => {
      let desiredWeights: BigNumber[];
      beforeEach('call make9901 function', async () => {
        desiredWeights = toNormalizedWeights([fp(99), fp(1)]);
        weightChanger = await deployController(deployer);
        await weightChanger.make9901();
      });

      it('Failure after 4 days', async () => {
        await fastForward(time.DAY * 4);
        assert.isNotTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });

      it('Successful after 8 days', async () => {
        await fastForward(time.DAY * 8);
        assert.isTrue(await checkTokenWeights(await weightChanger.getCurrentWeights(), desiredWeights));
      });
    });
  });

  async function checkTokenWeights(_tokenWeights: BigNumber[], _desiredWeights: BigNumber[]): Promise<boolean> {
    const tokenCount = (await weightChanger.getPoolTokens()).length - 1;
    let correctWeights = 0;

    for (let i = 0; i < tokenCount; i++) {
      if (_desiredWeights[i].toString() === _tokenWeights[i].toString()) {
        correctWeights += 1;
      }
    }
    return correctWeights == tokenCount ? true : false;
  }
});
