import { expect, use } from 'chai';
import { Contract, ethers, BigNumber, constants } from 'ethers';
import { deployContract, MockProvider, solidity } from 'ethereum-waffle';

// import LPMining from '../build/LPMining.json';
import FixedSupplyToken from '../build_cache/Token.json';
// import ETToken from '../build/ETToken.json';
// import WETH from '../build/WETH.json';
// import Recommend from '../build/Recommend.json';
// import InviteReward from '../build/InviteReward.json';
// import PledgeMining from '../build/PledgeMining.json';

import ERC20Token from '../build/ERC20.json';
import TickMathTest from '../build_cache/TickMathTest.json'
import LiquidityMathTest from '../build_cache/LiquidityAmountsTest.json'
import MulBank from '../build/MulBank.json';
import MulWork from '../build/MulWork.json';
import UniswapV3Strategy from '../build/UniswapV3Strategy.json'


import NonfungiblePositionManager from '../build_cache/NonfungiblePositionManager.json';
import NonfungibleTokenPositionDescriptor from '../build_cache/NonfungibleTokenPositionDescriptor.json';
import SwapRouter from '../build_cache/SwapRouter.json';
import UniswapV3Factory from '../build_cache/UniswapV3Factory.json';
import UniswapV3Pool from '../build_cache/UniswapV3Pool.json';
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

const deadline = 1626298638;
const spacing = TICK_SPACINGS[FeeAmount.MEDIUM];

import WETH9 from '../build_cache/WETH.json';


import { BigNumber as BN } from 'bignumber.js'

use(solidity);

function convertBigNumber(bnAmount: any, divider: number = 18) {
    return new BN(bnAmount.toString()).dividedBy(new BN(Math.pow(10, divider))).toFixed();
}

function toTokenAmount(amount: string, decimals: number = 18) {
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
    let strategy: Contract;
    // let v3PoolDeployer: Contract;
    // let tickMath: Contract;
    // let liquidityMath: Contract;

    let mulBank: Contract;
    let mulWork: Contract;

    let weth: Contract;
    let usdt: Contract;
    let dai: Contract;
    let btc: Contract;
    let gp: Contract;
    let mul: Contract;
    
    let poolUSDT2BTC: Contract;

    let swapTargetCallee: Contract;
    // let inviteReward: Contract;
    // let lpMining: Contract;
    // let mdexRouter: Contract;
    // let etQuery: Contract;
    // let nodeMining: Contract;

    let tx: any;
    let receipt: any;

    let pools;
    let wallets = {
      1: {
        name: "wallet1",
        wallet: wallet1
      },
      2: {
        name: "wallet2",
        wallet: wallet2
      },
    }

    function getWallet(key: any) {
      return wallets[key].wallet;
    }

    function getWalletName(key: any) {
      return wallets[key].name;
    }

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

    // async function addFullLiquidity() {
    //   const [t0, t1] = sortedTokens(usdt, btc)
    //   const param = {
    //         token0: t0.address,
    //         token1: t1.address,
    //         fee: FeeAmount.MEDIUM,
    //         tickLower: getMinTick(spacing),
    //         tickUpper: getMaxTick(spacing),
    //         amount0Desired: toTokenAmount('1000000'),
    //         amount1Desired: toTokenAmount('1000000'),
    //         amount0Min: 0,
    //         amount1Min: 0,
    //         recipient: deployer.address,
    //         deadline: deadline,
    //     }

    //     console.log(`developer balance usdt: ${convertBigNumber(await usdt.balanceOf(deployer.address))} 
    //     balance btc: ${convertBigNumber(await btc.balanceOf(deployer.address))}
    //     `)
    //     await (await NFTPositionManager.connect(deployer).mint(param, {gasLimit: 8000000})).wait();
    //     console.log(`developer balance usdt: ${convertBigNumber(await usdt.balanceOf(deployer.address))} 
    //     balance btc: ${convertBigNumber(await btc.balanceOf(deployer.address))}
    //     `)
    // }



    async function deployBank() {
      console.log("deployBank");
      mulBank = await deployContract(deployer, MulBank);
      await (await mulBank.connect(deployer).setStrategy(strategy.address)).wait();
      await (await mulBank.connect(deployer).initPool(usdt.address)).wait();
      await (await mulBank.connect(deployer).initPool(btc.address)).wait();
      await (await mulBank.connect(deployer).initPool(dai.address)).wait();
      console.log("complete");
    }

    async function deployWork() {
        console.log("deployWork");
        mulWork = await deployContract(deployer, MulWork, [gp.address, mul.address, mulBank.address]);
        await (await mulWork.connect(deployer).setStrategy(strategy.address)).wait();
        console.log("complete");
    }

    function getLog(x: any, y: any) {
       return Math.log(y) / Math.log(x);
    }

    async function depositToBank() {
      await (await mulBank.connect(wallet1).withdraw(usdt.address, toTokenAmount('5000'))).wait();
      await (await mulBank.connect(wallet2).withdraw(usdt.address, toTokenAmount('5000'))).wait();

      await (await mulBank.connect(wallet1).withdraw(btc.address, toTokenAmount('5000'))).wait();
      await (await mulBank.connect(wallet2).withdraw(btc.address, toTokenAmount('5000'))).wait();
    }



    before(async () => {
      // new bn(reserve1.toString())
      // console.log(encodePriceSqrt(1, 10000), encodePriceSqrt(10000, 1));
        // let u1 = Number(convertBigNumber(encodePriceSqrt(1, 10000)));
        // let u2 = Number(convertBigNumber(encodePriceSqrt(10000, 1)));

        // console.log(getLog(1.0001, encodePriceSqrt(1, 10000)), getLog(1.0001, encodePriceSqrt(10000, 1)));
        // tickMath     = await deployContract(deployer, TickMathTest);
        // liquidityMath     = await deployContract(deployer, LiquidityMathTest);
        weth         = await deployContract(deployer, WETH9);
        v3Factory    = await deployContract(deployer, UniswapV3Factory);
        v3Router     = await deployContract(deployer, SwapRouter, [v3Factory.address, weth.address]);
        strategy     = await deployContract(deployer, UniswapV3Strategy, [v3Factory.address]);

        NFTPositionDescriptor  = await deployContract(deployer, NonfungibleTokenPositionDescriptor, [weth.address]);
        NFTPositionManager     = await deployContract(deployer, NonfungiblePositionManager, [v3Factory.address, weth.address, NFTPositionDescriptor.address]);

        usdt         = await deployContract(deployer, FixedSupplyToken, ["USDT", "Tether USD", 18, 100000000]);
        dai          = await deployContract(deployer, FixedSupplyToken, ["DAI", "DAI Stable Coin", 18, 100000000]);
        btc          = await deployContract(deployer, FixedSupplyToken, ["BTC", "Bitcoin", 18, 100000000]);

        gp          = await deployContract(deployer, FixedSupplyToken, ["GP", "GP File", 18, 100000000]);
        mul          = await deployContract(deployer, FixedSupplyToken, ["MUL", "MulCoin", 18, 100000000]);

        await deployBank();

        await usdt.connect(deployer).transfer(wallet1.address, toTokenAmount('1000000', 18));
        await btc.connect(deployer).transfer(wallet1.address, toTokenAmount('1000000', 18));
        await dai.connect(deployer).transfer(wallet1.address, toTokenAmount('1000000', 18));

        await usdt.connect(deployer).transfer(wallet2.address, toTokenAmount('1000000', 18));
        await btc.connect(deployer).transfer(wallet2.address, toTokenAmount('1000000', 18));
        await dai.connect(deployer).transfer(wallet2.address, toTokenAmount('1000000', 18));

        await usdt.connect(deployer).approve(NFTPositionManager.address, constants.MaxUint256);
        await btc.connect(deployer).approve(NFTPositionManager.address, constants.MaxUint256);
        await dai.connect(deployer).approve(NFTPositionManager.address, constants.MaxUint256);

        await usdt.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);
        await btc.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);
        await dai.connect(wallet1).approve(NFTPositionManager.address, constants.MaxUint256);

        await usdt.connect(wallet2).approve(NFTPositionManager.address, constants.MaxUint256);
        await btc.connect(wallet2).approve(NFTPositionManager.address, constants.MaxUint256);
        await dai.connect(wallet2).approve(NFTPositionManager.address, constants.MaxUint256);

        await usdt.connect(wallet1).approve(mulBank.address, constants.MaxUint256);
        await btc.connect(wallet1).approve(mulBank.address, constants.MaxUint256);
        await dai.connect(wallet1).approve(mulBank.address, constants.MaxUint256);

        await usdt.connect(wallet1).approve(strategy.address, constants.MaxUint256);
        await btc.connect(wallet1).approve(strategy.address, constants.MaxUint256);
        await dai.connect(wallet1).approve(strategy.address, constants.MaxUint256);

        await usdt.connect(wallet2).approve(strategy.address, constants.MaxUint256);
        await btc.connect(wallet2).approve(strategy.address, constants.MaxUint256);
        await dai.connect(wallet2).approve(strategy.address, constants.MaxUint256);

        await usdt.connect(wallet2).approve(mulBank.address, constants.MaxUint256);
        await btc.connect(wallet2).approve(mulBank.address, constants.MaxUint256);
        await dai.connect(wallet2).approve(mulBank.address, constants.MaxUint256);
    });

    // it('deposit and withdraw', async() => {
    //     await (await mulBank.connect(wallet1).deposit(usdt.address, toTokenAmount('10000'))).wait();
    //     await (await mulBank.connect(wallet2).deposit(usdt.address, toTokenAmount('10000'))).wait();

    //     console.log("after deposit");

    //     await outputBalance(1);
    //     await outputBalance(2);

    //     await (await mulBank.connect(wallet1).withdraw(usdt.address, toTokenAmount('5000'))).wait();
    //     await (await mulBank.connect(wallet2).withdraw(usdt.address, toTokenAmount('5000'))).wait();

    //     console.log("after withdraw");
    //     await outputBalance(1);
    //     await outputBalance(2);
    // })  

    it('create account and invest', async() => {
        await depositToBank();

        console.log("create initial pool and price");
        let initPrice = encodePriceSqrt(1, 1);
        const [t0, t1] = sortedTokens(usdt, btc)
        await (await NFTPositionManager.createAndInitializePoolIfNecessary(
            t0.address,
            t1.address,
            FeeAmount.MEDIUM,
            initPrice
        )).wait();

        console.log("create an account ")
    })

    // it('add position', async() => {
    //     const [t0, t1] = sortedTokens(usdt, btc)
    //     let initPrice = encodePriceSqrt(1, 1);

    //     // create USDT-BTC medium fee pool
    //     console.log("初始价格usdt:btc 10000: 1");
        // await (await NFTPositionManager.createAndInitializePoolIfNecessary(
        //     t0.address,
        //     t1.address,
        //     FeeAmount.MEDIUM,
        //     initPrice
        // )).wait();

    //     console.log("添加流动性 10000: 1");
    //     await addFullLiquidity();

    //     console.log("添加存款 10000u");
    //     await depositToBank();

    //     let pool = v3Factory.getPool(t0.address, t1.address, FeeAmount.MEDIUM);
    //     let poolContract = new Contract(pool, UniswapV3Pool.abi, provider);

    //     const {
    //       sqrtPriceX96,
    //       tick,
    //       observationIndex,
    //       observationCardinality,
    //       observationCardinalityNext,
    //       feeProtocol,
    //       unlocked

    //     } = await poolContract.slot0();

    //     console.log(sqrtPriceX96, tick, observationIndex, observationCardinality);
    //     await addLimitLiquidity();
    //     // console.log("投资100u 100倍杠杆, 买btc");
    //     // await (await mulExchange.connect(wallet2).long(usdt.address, btc.address,
    //     //  toTokenAmount('100'), toTokenAmount('100'), 0, {gasLimit: 8000000})).wait();

    //     // const {
    //     //   sqrtPriceX96,
    //     //   tick,
    //     //   observationIndex,
    //     //   observationCardinality,
    //     //   observationCardinalityNext,
    //     //   feeProtocol,
    //     //   unlocked

    //     // } = await poolContract.slot0();

    //     // console.log(Number(sqrtPriceX96), tick, observationIndex, observationCardinality);
        

    //     // await outputExchangeBalance();
    //     // let balance = await btc.balanceOf(mulExchange.address)
    //     // console.log(2);
    //     // // let tick2 = await mulExchange.getTick(toTokenAmount("10000"), balance);
    //     // // tick = 0
    //     // // console.log();
    //     // let tick1 = await mulExchange.getTick(balance, toTokenAmount("10000"));
    //     // console.log(11, tick, tick1);
    //     // tick1 = 92160;
    //     // // console.log(await mulExchange.getTick(balance, toTokenAmount("10000")));
    //     // await outputBalance(2);
    //     // console.log(3);
    //     // const param = {
    //     //     token0: t0.address,
    //     //     token1: t1.address,
    //     //     fee: FeeAmount.MEDIUM,
    //     //     tickLower: tick1,
    //     //     tickUpper: tick1 + spacing,
    //     //     amount0Desired: balance,
    //     //     amount1Desired: 0,
    //     //     amount0Min: balance,
    //     //     amount1Min: 0,
    //     //     recipient: wallet2.address,
    //     //     deadline: deadline,
    //     // }

    //     // // await outputExchangeBalance();
    //     // await (await NFTPositionManager.connect(wallet2).mint(param, {gasLimit: 8000000})).wait();
    //     // await outputBalance(2);
    // });

    async function outputExchangeBalance() {
      console.log(`exchange balance usdt: ${convertBigNumber(await usdt.balanceOf(mulExchange.address))} 
        balance btc: ${convertBigNumber(await btc.balanceOf(mulExchange.address))}
        `)
    }

    async function outputPosition(id: any) {

    }

    async function outputBalance(key: any) {
      console.log(`${getWalletName(key)} balance usdt: ${convertBigNumber(await usdt.balanceOf(getWallet(key).address))} 
        balance btc: ${convertBigNumber(await btc.balanceOf(getWallet(key).address))}
        bank usdt: ${convertBigNumber(await usdt.balanceOf(mulBank.address))}
        bank btc: ${convertBigNumber(await btc.balanceOf(mulBank.address))}
        `)
    }

});