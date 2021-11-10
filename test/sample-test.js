const { expect } = require("chai");

let { constants, BigNumber } = require('ethers');
let UniswapV3Factory = require('../abi/UniswapV3Factory.json');
let SwapRouter = require('../abi/SwapRouter.json');
let NonfungiblePositionManager = require('../abi/NonfungiblePositionManager.json');
let NonfungibleTokenPositionDescriptor = require('../abi/NonfungibleTokenPositionDescriptor.json');

let address0 = "0x0000000000000000000000000000000000000000";
let BN = require("bignumber.js");
const FeeAmount = {
  LOW: 500,
  MEDIUM: 3000,
  HIGH: 10000,
}

const deadline = 1658164432;
const tickSpacing = 60
const getMinTick = (tickSpacing) => Math.ceil(-887272 / tickSpacing) * tickSpacing
const getMaxTick = (tickSpacing) => Math.floor(887272 / tickSpacing) * tickSpacing

const encodePriceSqrt = (reserve1, reserve0) => 
    new BN(reserve1.toString())
      .div(new BN(reserve0.toString()))
      .sqrt()
      .multipliedBy(new BN(2).pow(96))
      .integerValue(3)
      .toFixed()


function sortedTokens(
  a,
  b
){
  return a.address.toLowerCase() < b.address.toLowerCase() ? [a, b] : [b, a]
}

function encodePath(path, fees) {
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

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

const toMathAmount = (amount, decimals = 18) => new BN(amount.toString()).dividedBy(new BN(Math.pow(10, decimals))).toFixed();

describe("Invest", function() {
    let usdc, eth, uni, gp, mul;
    let ERC20;
    let bank, work, factory, positionManager, positionDescripter, router, weth;
    let deployer, lp1, lp2, gp1, gp2;

    async function initWork() {
        console.log("deployWork");
        await (await work.addPermission(strategy.address)).wait();
        await (await work.setExtraQuota(gp1.address, [weth.address], [toTokenAmount("0.05")])).wait();
        await (await work.setBaseQuota([usdc.address, eth.address, weth.address], [toTokenAmount('10000'), toTokenAmount('10000'), toTokenAmount("0.05")])).wait();
        console.log("complete");
    }

    async function initBank() {
      console.log("deployBank");
      await (await bank.addPermission(strategy.address)).wait();
      await (await bank.initPool(usdc.address)).wait();
      await (await bank.initPool(uni.address)).wait();
      await (await bank.initPool(eth.address)).wait();
      await (await bank.initPool(weth.address)).wait();

      await (await bank.addRemains([usdc.address, uni.address, eth.address, weth.address], [toTokenAmount('1000000'), toTokenAmount('1000000'), toTokenAmount('1000000'), toTokenAmount('1000000')]))
      console.log("complete");
    }

    async function approveAndTransfer() {
      await usdc.transfer(lp1.address, toTokenAmount('1000000'));
      await eth.transfer(lp1.address, toTokenAmount('1000000'));
      await uni.transfer(lp1.address, toTokenAmount('1000000'));

      await usdc.transfer(lp2.address, toTokenAmount('1000000'));
      await eth.transfer(lp2.address, toTokenAmount('1000000'));
      await uni.transfer(lp2.address, toTokenAmount('1000000'));

      await usdc.transfer(gp1.address, toTokenAmount('1000000'));
      await eth.transfer(gp1.address, toTokenAmount('1000000'));
      await uni.transfer(gp1.address, toTokenAmount('1000000'));

      await usdc.approve(positionManager.address, constants.MaxUint256);
      await eth.approve(positionManager.address, constants.MaxUint256);
      await uni.approve(positionManager.address, constants.MaxUint256);


      await usdc.approve(router.address, constants.MaxUint256);
      await eth.approve(router.address, constants.MaxUint256);
      await uni.approve(router.address, constants.MaxUint256);

      await usdc.connect(lp2).approve(bank.address, constants.MaxUint256);
        await eth.connect(lp2).approve(bank.address, constants.MaxUint256);
        await uni.connect(lp2).approve(bank.address, constants.MaxUint256);

        await usdc.connect(lp1).approve(bank.address, constants.MaxUint256);
        await eth.connect(lp1).approve(bank.address, constants.MaxUint256);
        await uni.connect(lp1).approve(bank.address, constants.MaxUint256);

        await usdc.connect(gp1).approve(strategy.address, constants.MaxUint256);
        await eth.connect(gp1).approve(strategy.address, constants.MaxUint256);
        await uni.connect(gp1).approve(strategy.address, constants.MaxUint256);

        await usdc.connect(gp2).approve(strategy.address, constants.MaxUint256);
        await eth.connect(gp2).approve(strategy.address, constants.MaxUint256);
        await uni.connect(gp2).approve(strategy.address, constants.MaxUint256);

        await gp.connect(gp1).approve(work.address, 1);
        await gp.connect(gp2).approve(work.address, 2);
    }

    async function depositToBank() {
      await (await bank.connect(lp1).deposit(usdc.address, toTokenAmount('5000'))).wait();
      await (await bank.connect(lp2).deposit(usdc.address, toTokenAmount('5000'))).wait();

      await (await bank.connect(lp1).deposit(eth.address, toTokenAmount('5000'))).wait();
      await (await bank.connect(lp2).deposit(eth.address, toTokenAmount('5000'))).wait();

      await (await bank.connect(lp1).deposit(uni.address, toTokenAmount('5000'))).wait();
      await (await bank.connect(lp2).deposit(uni.address, toTokenAmount('5000'))).wait();

      await (await bank.connect(lp1).deposit(weth.address, toTokenAmount('1'), {value: toTokenAmount('1')})).wait();
      await (await bank.connect(lp2).deposit(weth.address, toTokenAmount('1'), {value: toTokenAmount('1')})).wait();

    }

    async function swap(from, to, amount) {
    let params = {
              recipient: develop.address,
              deadline: deadline,
              path: encodePath([from.address, to.address], [FeeAmount.MEDIUM]),
              amountIn: amount,
              amountOutMinimum: 0,
        }
        let value = from.address===weth.address ? amount: 0;
        await (await router.exactInput(params, {gasLimit: 8000000, value: value})).wait();
        console.log("swap complete");
    }

    before(async () => {
        console.log("deploy coin");

        [develop, lp1, lp2, gp1, gp2] = await ethers.getSigners()

        ERC20 = await ethers.getContractFactory("Token");
        usdc = await ERC20.deploy("USDC", "Tether USDC", 18, 100000000);
        eth = await ERC20.deploy("ETH", "ETH Coin", 18, 100000000);
        uni = await ERC20.deploy("UNI", "UNI Coin", 18, 100000000);
        mul = await ERC20.deploy("MUL", "MUL Coin", 18, 100000000);

        ERC721 = await ethers.getContractFactory("Pop721");
        gp = await ERC721.deploy("GP Worker", "GP", "");
        await gp.mint(gp1.address, 1);
        await gp.mint(gp2.address, 2);

        const WETH = await ethers.getContractFactory("WETH9");
        weth = await WETH.deploy();

        const Factory = await ethers.getContractFactory(UniswapV3Factory.abi, UniswapV3Factory.bytecode);
        factory = await Factory.deploy();

        const Descripter = await ethers.getContractFactory(NonfungibleTokenPositionDescriptor.abi, NonfungibleTokenPositionDescriptor.bytecode);
        positionDescripter = await Descripter.deploy(weth.address);

        const PositionManager = await ethers.getContractFactory(NonfungiblePositionManager.abi, NonfungiblePositionManager.bytecode);
        positionManager = await PositionManager.deploy(factory.address, weth.address, positionDescripter.address);

        const Router = await ethers.getContractFactory(SwapRouter.abi, SwapRouter.bytecode);
        router = await Router.deploy(factory.address, weth.address);

        const Bank = await ethers.getContractFactory("MulBank");
        bank = await Bank.deploy(weth.address);

        const Work = await ethers.getContractFactory("MulWork");
        work = await Work.deploy(gp.address, bank.address);

        const Strategy = await ethers.getContractFactory("UniswapV3Strategy");
        strategy     = await Strategy.deploy(factory.address, work.address, bank.address);

        await initBank();
        await initWork();
        await approveAndTransfer();
    });

    async function addFullLiquidity() {
      const [t0, t1] = sortedTokens(usdc, weth)
      const param = {
            token0: t0.address,
            token1: t1.address,
            fee: FeeAmount.MEDIUM,
            tickLower: getMinTick(tickSpacing),
            tickUpper: getMaxTick(tickSpacing),
            amount0Desired: toTokenAmount('1'),
            amount1Desired: toTokenAmount('1'),
            amount0Min: 0,
            amount1Min: 0,
            recipient: develop.address,
            deadline: deadline,
        }

        console.log(`developer balance usdc: ${toMathAmount(await usdc.balanceOf(develop.address))} 
        balance eth: ${toMathAmount(await eth.balanceOf(develop.address))}
        `)
        await (await positionManager.mint(param, {gasLimit: 8000000, value:toTokenAmount(1)})).wait();
        console.log(`developer balance usdc: ${toMathAmount(await usdc.balanceOf(develop.address))} 
        balance eth: ${toMathAmount(await eth.balanceOf(develop.address))}
        `)
    }


     it("deposit bank", async function () {
        // await 
        await depositToBank();
      });

     it("invest", async function () {
        // await 
        const [t0, t1] = sortedTokens(usdc, weth)
        await (await positionManager.createAndInitializePoolIfNecessary(
            t0.address,
            t1.address,
            FeeAmount.MEDIUM,
            encodePriceSqrt(1, 1)
        )).wait();

        console.log("add full liquidity");
        await addFullLiquidity();

        console.log("create an account");
        await (await work.connect(gp1).createAccount(1)).wait();
        await (await work.connect(gp2).createAccount(2)).wait();

        const param = {
            token0: t0.address,
            token1: t1.address,
            fee: FeeAmount.MEDIUM,
            tickLower: -600,
            tickUpper: 600,
            amount0Desired: toTokenAmount('0.1'),
            amount1Desired: toTokenAmount('0.1'),
        }
        await (await strategy.connect(gp1).invest(param, {gasLimit: 8000000})).wait();

        console.log("simulate swap");
        await swap(usdc, weth, toTokenAmount("0.2"));
        await swap(weth, usdc, toTokenAmount("2000"));

        console.log(`gp1 balance usdc: ${toMathAmount(await usdc.balanceOf(gp1.address))} 
        balance eth: ${toMathAmount(await gp1.getBalance())}
        `)

        // await (await strategy.connect(gp1).divest(0, true, {gasLimit: 8000000, value:toTokenAmount(1.5)})).wait();

        console.log(`gp1 balance usdc: ${toMathAmount(await usdc.balanceOf(gp1.address))} 
        balance eth: ${toMathAmount(await gp1.getBalance())}
        `)

        console.log(`bank balance usdc: ${toMathAmount(await usdc.balanceOf(bank.address))} 
        balance eth: ${toMathAmount(await eth.balanceOf(bank.address))}
        `)

        // await (await bank.connect(lp1).withdraw(usdc.address, toTokenAmount('5000'))).wait();
        // await (await bank.connect(lp2).withdraw(usdc.address, toTokenAmount('5000'))).wait();

        // await (await bank.connect(lp1).withdraw(weth.address, toTokenAmount('1'))).wait();
        // await (await bank.connect(lp2).withdraw(weth.address, toTokenAmount('1'))).wait();

        console.log(`lp1 balance usdc: ${toMathAmount(await usdc.balanceOf(lp1.address))} 
        balance eth: ${toMathAmount(await lp1.getBalance())}
        `)

        console.log(`lp2 balance usdc: ${toMathAmount(await usdc.balanceOf(lp2.address))} 
        balance eth: ${toMathAmount(await lp1.getBalance())}
        `)

        let xx = await strategy.connect(gp1).callStatic.collect(0);
        console.log(toMathAmount(xx.fee0),toMathAmount(xx.fee1));


        let swit = {
            tickLower: -600,
            tickUpper: 600,
            amount0Desired: toTokenAmount('0.1'),
            amount1Desired: toTokenAmount('0.1'),
        }
        await (await strategy.connect(gp1).switching(0, swit, false, {gasLimit: 8000000})).wait()
        // console.log(aa);
        xx = await strategy.connect(gp1).callStatic.collect(0);
        console.log(toMathAmount(xx.fee0),toMathAmount(xx.fee1));
      });
})
