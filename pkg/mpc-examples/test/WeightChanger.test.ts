import { assert /* expect */ } from 'chai';
import { ethers } from 'hardhat';
import { bn, fp } from '@orbcollective/shared-dependencies/numbers';
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import { getBalancerContractArtifact } from '@balancer-labs/v2-deployments';
import * as expectEvent from '@orbcollective/shared-dependencies/expectEvent';

import { TokenList, setupEnvironment, deployToken, deployWETH } from '@orbcollective/shared-dependencies';
import { toNormalizedWeights } from '@balancer-labs/balancer-js';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

let deployer: SignerWithAddress;
let mpcFactory: Contract;
let tokenAddresses: string[];
let weightChanger: Contract;

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

    const receipt = await (await mpcFactory.connect(deployer).create()).wait();
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

    before('Setup', async () => {
        let trader, liquidityProvider;
        ({ vault, deployer, trader, liquidityProvider } = await setupEnvironment());

        const pfpArgs = [vault.address, fp(0.1), fp(0.1)];
        const protocolFeesProvider = await deployBalancerContract(
            '20220725-protocol-fee-percentages-provider/',
            'ProtocolFeePercentagesProvider',
            deployer,
            pfpArgs
        );

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
    })

    describe('Controller Deployment', () => {
        beforeEach('deploy', async () => {
            const args = [vault.address];
            weightChanger = await deployController(deployer);
        });

        it("Local Controller's Vault is the Vault", async () => {
            assert.equal(vault.address, await weightChanger.getVault());
        });

        it('Deploys managed pool; controller set as AM for all tokens', async () => {
            const poolId = await weightChanger.getPoolId();
            const tokens = await weightChanger.getPoolTokens();
            // We start at index 1 because the first token returned in get pool tokens is BPT
            for (let i = 1;i < tokens.length;i++) {
                const info = await vault.getPoolTokenInfo(poolId, tokens[i]);
                assert.equal(info.assetManager, weightChanger.address);
            }
        });
    });


});