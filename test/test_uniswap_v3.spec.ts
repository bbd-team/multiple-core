import { expect, use } from 'chai';
import { Contract, ethers, BigNumber, constants } from 'ethers';
import { deployContract, MockProvider, solidity } from 'ethereum-waffle';

// import LPMining from '../build/LPMining.json';
import FixedSupplyToken from '../build/Token.json';
// import ETToken from '../build/ETToken.json';
// import WETH from '../build/WETH.json';
// import Recommend from '../build/Recommend.json';
// import InviteReward from '../build/InviteReward.json';
// import PledgeMining from '../build/PledgeMining.json';

import ERC20Token from '../build/ERC20.json';
import MockTimeNonfungiblePositionManager from '../build/MockTimeNonfungiblePositionManager.json';
import NonfungibleTokenPositionDescriptor from '../build/NonfungibleTokenPositionDescriptor.json';
import SwapRouter from '../build/SwapRouter.json';
import UniswapV3Factory from '../build/UniswapV3Factory.json';
import {
  createPoolFunctions,
  encodePriceSqrt,
  expandTo18Decimals,
  FeeAmount,
  getMaxLiquidityPerTick,
  getMaxTick,
  getMinTick,
  MAX_SQRT_RATIO,
  MaxUint128,
  MIN_SQRT_RATIO,
  TICK_SPACINGS,
} from './shared/utilities'

import WETH9 from '../build/WETH.json';


import { BigNumber as BN } from 'bignumber.js'

use(solidity);

function convertBigNumber(bnAmount: any, divider: number) {
    return new BN(bnAmount.toString()).dividedBy(new BN(divider)).toFixed();
}
function toTokenAmount(amount: string, decimals: number) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

function compareToken(a: { address: string }, b: { address: string }): -1 | 1 {
  return a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1
}

function sortedTokens(
  a: { address: string },
  b: { address: string }
): [typeof a, typeof b] | [typeof b, typeof a] {
  return compareToken(a, b) < 0 ? [a, b] : [b, a]
}

function encodePath(path: string[], fees: FeeAmount[]): string {
  if (path.length != fees.length + 1) {
    throw new Error('path/fee lengths do not match')
  }

  let encoded = '0x'
  for (let i = 0; i < fees.length; i++) {
    // 20 byte encoding of the address
    encoded += path[i].slice(2)
    // 3 byte encoding of the fee
    encoded += fees[i].toString(16).padStart(2 * 3, '0')
  }
  // encode the final token
  encoded += path[path.length - 1].slice(2)

  return encoded.toLowerCase()
}



let address0 = "0x0000000000000000000000000000000000000000";

describe('Test Uniswap V3', () => {
    let provider = new MockProvider({ ganacheOptions: { gasLimit: 8000000 } });
    const [deployer, wallet1, wallet2, wallet3, wallet4] = provider.getWallets();

    let NFTPositionManager: Contract;
    let NFTPositionDescriptor: Contract;
    let v3Router: Contract;
    let v3Factory: Contract;
    let v3PoolDeployer: Contract;

    let weth: Contract;
    let usdt: Contract;
    let dai: Contract;
    let btc: Contract;
    
    let poolUSDT2BTC: Contract;

    let swapTargetCallee: Contract;
    // let inviteReward: Contract;
    // let lpMining: Contract;
    // let mdexRouter: Contract;
    // let etQuery: Contract;
    // let nodeMining: Contract;

    let tx: any;
    let receipt: any;

    async function getBlockNumber() {
        const blockNumber = await provider.getBlockNumber()
        console.log("Current block number: " + blockNumber);
        return blockNumber;
    }

    async function mineBlock(provider: MockProvider, count: number): Promise<void> {
        console.log("wait mine block count " + count)
        for (let i = 0; i < count; i++) {
            await provider.send('evm_mine', [parseInt((Date.now() / 1000).toString())])
        }
    }

    before(async () => {

        weth         = await deployContract(deployer, WETH9);
        v3Factory    = await deployContract(deployer, UniswapV3Factory);
        v3Router     = await deployContract(deployer, SwapRouter, [v3Factory.address, weth.address]);
        NFTPositionDescriptor  = await deployContract(deployer, NonfungibleTokenPositionDescriptor, [weth.address]);
        NFTPositionManager     = await deployContract(deployer, MockTimeNonfungiblePositionManager, [v3Factory.address, weth.address, NFTPositionDescriptor.address]);

        usdt         = await deployContract(deployer, FixedSupplyToken, ["USDT", "Tether USD", 18, 100000000]);
        dai          = await deployContract(deployer, FixedSupplyToken, ["DAI", "DAI Stable Coin", 18, 100000000]);
        btc          = await deployContract(deployer, FixedSupplyToken, ["BTC", "Bitcoin", 18, 100000000]);

        await usdt.connect(deployer).transfer(wallet1.address, toTokenAmount('1000', 18));
        await btc.connect(deployer).transfer(wallet1.address, toTokenAmount('1000', 18));
        await dai.connect(deployer).transfer(wallet1.address, toTokenAmount('1000', 18));

        await usdt.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);
        await btc.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);
        await dai.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);
        
    });

    it('add position', async() => {
        const [t0, t1] = sortedTokens(usdt, btc)

        const param = {
            token0: t0.address,
            token1: t1.address,
            fee: FeeAmount.MEDIUM,
            tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
            tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
            amount0Desired: 100,
            amount1Desired: 100,
            amount0Min: 0,
            amount1Min: 0,
            recipient: wallet1.address,
            deadline: 1,
        }

        // create USDT-BTC medium fee pool
        await NFTPositionManager.createAndInitializePoolIfNecessary(
            t0.address,
            t1.address,
            FeeAmount.MEDIUM,
            encodePriceSqrt(1, 1)
        );

        // add liquidity
        const position = await NFTPositionManager.connect(wallet1).mint(param, {gasLimit: 8000000});

        // console.log('position tokenId', convertBigNumber(position.tokenId, 1));

        // check my position
        const {
            fee,
            token0,
            token1,
            tickLower,
            tickUpper,
            liquidity,
            tokensOwed0,
            tokensOwed1,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
        } = await NFTPositionManager.positions(1);

        console.log(fee, token0, token1, tickLower, tickUpper, liquidity, tokensOwed0, tokensOwed1, feeGrowthInside0LastX128,  feeGrowthInside1LastX128);

        // swap
        await usdt.connect(wallet1).approve(v3Router.address, toTokenAmount('1000', 18));
        await v3Router.connect(wallet1).exactInput({
          recipient: wallet1.address,
          deadline: 10,
          path: encodePath([usdt.address, btc.address], [FeeAmount.MEDIUM]),
          amountIn: toTokenAmount('100', 18),
          amountOutMinimum: 0,
        });

        // remove liquidity
        await NFTPositionManager.connect(wallet1).decreaseLiquidity(1, 100, 0, 0, 1);
        await NFTPositionManager.connect(wallet1).collect(1, wallet1.address, MaxUint128, MaxUint128);
        await NFTPositionManager.connect(wallet1).burn(1);
    });
});