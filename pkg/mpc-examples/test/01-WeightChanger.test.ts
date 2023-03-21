import { assert, expect } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';
import * as time from '@orbcollective/shared-dependencies/time';
import { pickTokenAddresses, setupEnvironment, TokenList } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';
import { BigNumber } from 'ethers';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress;
let rando: SignerWithAddress;
let mpcFactory: Contract;
let weightChangerController: Contract;
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

  return ethers.getContractAt('WeightChangerController', eventController.args.controller);
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

describe('WeightChangerController', () => {
  let vault: Contract;
  let tokens: TokenList;
  let trader: SignerWithAddress;

  before('Setup', async () => {
    ({ vault, tokens, deployer, trader } = await setupEnvironment());

    rando = trader;

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
    mpcFactory = await deployLocalContract('WeightChangerControllerFactory', deployer, controllerFactoryArgs);
  });

  describe('Controller Deployment', () => {
    beforeEach('deploy', async () => {
      weightChangerController = await deployController(deployer);
    });

    it("Local Controller's Vault is the Vault", async () => {
      assert.equal(vault.address, await weightChangerController.getVault());
    });

    it('Deploys managed pool; controller set as AM for all tokens', async () => {
      const poolId = await weightChangerController.getPoolId();
      const tokens = await weightChangerController.getTokens();

      for (let i = 0; i < tokens.length; i++) {
        const info = await vault.getPoolTokenInfo(poolId, tokens[i]);
        assert.equal(info.assetManager, weightChangerController.address);
      }
    });

    it('Initial weights are set 30/70', async () => {
      assert.isTrue(await checkTokenWeights(await weightChangerController.getCurrentWeights(), initialWeights));
    });

    it('Reweight duration set at 7 days', async () => {
      assert.equal(await weightChangerController.getReweightDuration(), time.WEEK);
    });
  });

  // All weights are in terms of WETH/USDC
  describe('Change Managed Pool weights', () => {
    beforeEach('Deploy controller', async () => {
      weightChangerController = await deployController(deployer);
    });

    it('Change weights to 50/50', async () => {
      const weightGoals: BigNumber[] = toNormalizedWeights([fp(50), fp(50)]);
      await weightChangerController.make5050();
      assert.isTrue(await testWeightChange(weightGoals));
    });

    it('Change weights to 80/20', async () => {
      const weightGoals: BigNumber[] = toNormalizedWeights([fp(80), fp(20)]);
      await weightChangerController.make8020();
      assert.isTrue(await testWeightChange(weightGoals));
    });

    it('Change weights to 99/01', async () => {
      const weightGoals: BigNumber[] = toNormalizedWeights([fp(99), fp(1)]);
      await weightChangerController.make9901();
      assert.isTrue(await testWeightChange(weightGoals));
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

  async function checkTokenWeights(_tokenWeights: BigNumber[], _desiredWeights: BigNumber[]): Promise<boolean> {
    const tokenCount = (await weightChangerController.getTokens()).length;
    let correctWeights = 0;
    for (let i = 0; i < tokenCount; i++) {
      if (_desiredWeights[i].toString() === _tokenWeights[i].toString()) {
        correctWeights += 1;
      }
    }
    return correctWeights == tokenCount;
  }

  async function getDesiredWeights(
    _startingWeights: BigNumber[],
    _weightGoals: BigNumber[],
    interval: number,
    totalSteps: number
  ): Promise<BigNumber[]> {
    const desiredWeights: BigNumber[] = [];

    for (let i = 0; i < _startingWeights.length; i++) {
      const weightDifference = _weightGoals[i].sub(_startingWeights[i]);
      const stepAmount = weightDifference.div(BigNumber.from(totalSteps));
      const predictedWeight = _startingWeights[i].add(stepAmount.mul(BigNumber.from(interval)));
      desiredWeights.push(predictedWeight);
    }
    return desiredWeights;
  }

  async function testWeightChange(_weightGoals: BigNumber[]): Promise<boolean> {
    const intervals = 5;
    const timePerStep = (time.DAY * 7) / intervals;
    let accuracyCounter = 0;
    for (let i = 1; i <= intervals; i++) {
      await fastForward(timePerStep);

      const result = await checkTokenWeights(
        await weightChangerController.getCurrentWeights(),
        await getDesiredWeights(initialWeights, _weightGoals, i, intervals)
      );

      if (!result) {
        return false;
      } else {
        accuracyCounter++;
      }
    }
    return accuracyCounter == intervals;
  }
});
