// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const uniFactory = "0xE5B1C39b307A4338632D5D36E686013Ea2c63965";
const DAI = "0xbEd2BB278b4BBB20450F4E265bd5F250C1E6428c";
const UNI = "0xe034f90CDa2a219Db2D760Dff42c7085763C7424";
const USDC = "0xe6a4bF81116272205482d142760807C35A5F4909";
const ETH = "0xFA027A5D2298fc03fc2842F4877aa6A039b0109d";

const bank = "0x12435D6366c3DC367f8E3A0B9fc9E1A603ECFDc1"

let BN = require("bignumber.js");

let Pop721;
let MulBank;
let MulWork;
let ERC20;

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function addRemain() {
  MulBank = await hre.ethers.getContractFactory("MulBank");
  let bankContract = await hre.ethers.getContractAt("MulBank", bank);
  await (await bankContract.addRemains([DAI, UNI, USDC, ETH], 
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000")])
).wait()
    console.log("complete")
}

async function deposit(mulBank) {
  let bankContract = await hre.ethers.getContractAt("MulBank", mulBank.address);

  // await bankContract.addRemains([DAI, UNI, USDC, ETH], 
  //   [toTokenAmount("20000000"), toTokenAmount("20000000"), toTokenAmount("20000000", 6), toTokenAmount("20000000")])

  let daiContract = await hre.ethers.getContractAt("ERC20", DAI);
  let uniContract = await hre.ethers.getContractAt("ERC20", UNI);
  let usdcContract = await hre.ethers.getContractAt("ERC20", USDC);
  let ethContract = await hre.ethers.getContractAt("ERC20", ETH);

  console.log('approve');
  await (await daiContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();
  await (await uniContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();
  await (await usdcContract.approve(mulBank.address, toTokenAmount("10000000", 6))).wait();
  await (await ethContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();

  console.log('deposit')
  await (await bankContract.deposit(DAI, toTokenAmount("10000000"))).wait();
  await (await bankContract.deposit(UNI, toTokenAmount("10000000"))).wait();
  await (await bankContract.deposit(USDC, toTokenAmount("10000000", 6))).wait();
  await (await bankContract.deposit(ETH, toTokenAmount("10000000"))).wait();
}

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  Pop721 = await hre.ethers.getContractFactory("Pop721");
  MulBank = await hre.ethers.getContractFactory("MulBank");
  MulWork = await hre.ethers.getContractFactory("UniswapV3WorkCenter");
  ERC20 = await hre.ethers.getContractFactory("ERC20");
  const WETH = await hre.ethers.getContractFactory("WETH9")

  const WETH9 = await WETH.deploy();
  const pop721 = await Pop721.deploy("Multiple GP", "GP", "https://www.multiple.fi");
  const mulBank = await MulBank.deploy(WETH9.address);
  const mulWork = await MulWork.deploy(pop721.address);

  console.log("deploy");
  await (await mulBank.initPool(DAI)).wait();
  await (await mulBank.initPool(UNI)).wait();
  await (await mulBank.initPool(USDC)).wait();
  await (await mulBank.initPool(ETH)).wait();

  const Strategy = await hre.ethers.getContractFactory("UniswapV3Strategy");
  const strategy = await Strategy.deploy(uniFactory, mulWork.address, mulBank.address);

  await (await mulBank.addPermission(strategy.address)).wait();
  await (await mulWork.addPermission(strategy.address)).wait();

  // await (await mulWork.setQuotas([DAI, UNI, USDC, ETH], [toTokenAmount("100000"), toTokenAmount("5000"), toTokenAmount("100000", 6), toTokenAmount("100")])).wait();

  console.log('let mulBank: any = "' + mulBank.address + '"');
  console.log('let mulWork: any = "' + mulWork.address + '"');
  console.log('let strategy: any = "' + strategy.address + '"');
  console.log('let gp: any = "' + pop721.address + '"');

  await deposit(mulBank);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// addRemain();
