// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const uniFactory = "0x80a39Ed431B27F53587eC55331e41DadA01B8e96";
const DAI = "0x0a637e5fc9ef09ec7895923b90b5b8b88676e0e5";
const UNI = "0x68880631882c62121eebec75041e7be3544a553f";
const USDC = "0x6eea1236e58150c1a6598b4b30d8776fc59763c1";
const WETH9 = "0xc778417e063141139fce010982780140aa0cd5ab";
const IZI = "0xcd20fef1cff6355eb7cb9bc7a2f17fa4d84b6095";

const coinList = [USDC, UNI, WETH9, DAI, IZI];
const bank = "0x12435D6366c3DC367f8E3A0B9fc9E1A603ECFDc1"
const gpList = ["0x2D83750BDB3139eed1F76952dB472A512685E3e0", "0xd7f4a04c736cC1C5857231417E6cB8Da9cAdbEC7", "0xA768267D5b04f0454272664F4166F68CFc447346", "0xfdA074b94B1e6Db7D4BEB45058EC99b262e813A5",
 "0xc03C12101AE20B8e763526d6841Ece893248a069", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0",
  "0x3897A13FbC160036ba614c07D703E1fCbC422599"]

let BN = require("bignumber.js");

let Pop721;
let MulBank;
let MulWork;
let ERC20;
let owner = "0x2D83750BDB3139eed1F76952dB472A512685E3e0";


const poolList = ["0x660e1cadc3aa204ea063f14e3ca8efea19f2d42a",
 "0xb8f242266520ac910b6a8161eb3c4655e5c3c784", "0xdca4da2e137fba8aca8c14934da33edf9ab165af",
  "0xe01aaaea7eaccc19674aa13bbcbaea2add3bce6d", "0xea8b164aa3e589c864a468a917281ff07e2ef683", 
  "0x1e3406923cc4c19d47a2f09b4cd14edef11d25de", "0x089224e3ce16b04f3749201c1c9385c821a83545"]

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function addRemain(bank) {
  let bankContract = await hre.ethers.getContractAt("MulBank", bank);
  await (await bankContract.switchWhiteList(gpList, Array(gpList.length).fill(true))).wait();
    console.log("complete")
}

async function deposit(mulBank) {
  let bankContract = await hre.ethers.getContractAt("MulBank", mulBank.address);

  // await bankContract.addRemains([DAI, UNI, USDC, WETH9], 
  //   [toTokenAmount("20000000"), toTokenAmount("20000000"), toTokenAmount("20000000", 6), toTokenAmount("20000000")])

  let daiContract = await hre.ethers.getContractAt("ERC20", DAI);
  let uniContract = await hre.ethers.getContractAt("ERC20", UNI);
  let usdcContract = await hre.ethers.getContractAt("ERC20", USDC);
  // let ethContract = await hre.ethers.getContractAt("ERC20", WETH9);

  console.log('approve');
  await (await daiContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();
  await (await uniContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();
  await (await usdcContract.approve(mulBank.address, toTokenAmount("10000000", 6))).wait();
  // await (await ethContract.approve(mulBank.address, toTokenAmount("10000000"))).wait();

  console.log('deposit')
  // await (await bankContract.deposit(DAI, toTokenAmount("10000000"))).wait();
  // await (await bankContract.deposit(UNI, toTokenAmount("10000000"))).wait();
  // await (await bankContract.deposit(USDC, toTokenAmount("10000000", 6))).wait();
  // await (await bankContract.deposit(WETH9, toTokenAmount("10000000"), {value: toTokenAmount(10000000)})).wait();
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
  // const WETH = await hre.ethers.getContractFactory("WETH9")
  console.log("start");
  // WETH9 = await WETH.deploy();
  const pop721 = await Pop721.deploy("Multiple GP", "GP", "https://www.multiple.fi");
  console.log(1, pop721.address);
  const mulBank = await MulBank.deploy(WETH9);
  const mulWork = await MulWork.deploy(pop721.address);

  console.log("deploy");
  await (await mulBank.initPoolList(coinList, Array(coinList.length).fill(0))).wait();

  const Strategy = await hre.ethers.getContractFactory("UniswapV3Strategy");
  const strategy = await Strategy.deploy(uniFactory, mulWork.address, mulBank.address, owner);

  console.log("init");
  await (await mulBank.addPermission(strategy.address)).wait();
  await (await mulWork.addPermission(strategy.address)).wait();

  await (await mulWork.switchPool(poolList, Array(poolList.length).fill(true))).wait();

  for(let gp of gpList) {
    let tokenId = Math.floor(Math.random() * 1000000);
    await pop721.mint(gp, tokenId);
  }
  

  // await (await mulWork.setQuotas([DAI, UNI, USDC, ETH], [toTokenAmount("100000"), toTokenAmount("5000"), toTokenAmount("100000", 6), toTokenAmount("100")])).wait();

  console.log('let mulBank = "' + mulBank.address + '"');
  console.log('let UniswapV3WorkCenter = "' + mulWork.address + '"');
  console.log('let strategy = "' + strategy.address + '"');
  console.log('let gp = "' + pop721.address + '"');

  await deposit(mulBank);
  await addQuota(mulWork);
  await (await mulBank.switchWhiteList(gpList, Array(gpList.length).fill(true))).wait();
}

async function addQuota(work) {
  let workContract = await hre.ethers.getContractAt("UniswapV3WorkCenter", work);

  for(let gp of gpList) {
    await workContract.setQuota(gp, coinList,
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000"), toTokenAmount("10000000")]);

    // for(let token of [DAI, UNI, USDC, WETH9]) {
    //   let tokenContract = await hre.ethers.getContractAt("Token", token);
    //   let decimal = await tokenContract.decimals();
    //   await tokenContract.transfer(gp, toTokenAmount("100000", decimal));
    //   console.log("transfer", gp, token);
    // }
    
  }
   console.log("complete");


}

async function addPool(pool = "0xcd20fef1cff6355eb7cb9bc7a2f17fa4d84b6095", user = "0xd7f4a04c736cC1C5857231417E6cB8Da9cAdbEC7") {
    const bankContract = await hre.ethers.getContractAt("MulBank", "0xCBA153F464db90054Fb714d9E55b8934b1a19478");

    console.log("deploy");
    // await (await bankContract.initPoolList([IZI], [0])).wait();

    let iziContract = await hre.ethers.getContractAt("ERC20", IZI);
    console.log('approve');
    // await (await iziContract.approve(bankContract.address, toTokenAmount("10000000"))).wait();
    console.log('approve');
    // await (await bankContract.switchWhiteList(gpList, Array(gpList.length).fill(true))).wait();
    // await (await bankContract.deposit(IZI, toTokenAmount("10000000"))).wait();

    let workContract = await hre.ethers.getContractAt("UniswapV3WorkCenter", "0x4a4Ce239cA3D37BfBF2AF6De83895963c2Ad562d");

    let poolList = ["0x1e3406923cc4c19d47a2f09b4cd14edef11d25de", "0x089224e3ce16b04f3749201c1c9385c821a83545"];
    await workContract.switchPool(poolList, [true, true]);

    let popContract = await hre.ethers.getContractAt("Pop721", "0x93360C0b938b23b588cD8184405D8E25b05fcBef");
    let tokenId = Math.floor(Math.random() * 1000000);
  await popContract.mint(user, tokenId);
  console.log(1);

  for(let gp of gpList) {
    await workContract.setQuota(gp, [DAI, UNI, USDC, WETH9, IZI], 
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000"), toTokenAmount("10000000")]);
  }

console.log(2);
for(let token of [IZI, USDC]) {
      let tokenContract = await hre.ethers.getContractAt("Token", token);
      let decimal = await tokenContract.decimals();
      await tokenContract.transfer(user, toTokenAmount("100000", decimal));
      await tokenContract.transfer(user, toTokenAmount("100000", decimal));
      console.log("transfer", user, token);
    }
}

async function switchPool(work = "0xc14A128F54d985E86C776063D3EB13507cb96289") {
  let workContract = await hre.ethers.getContractAt("UniswapV3WorkCenter", work);
  // await workContract.switchPool(poolList, [false,true,false,false,false]);

  // await workContract.switchPool(oldList, [false,false,false,false,true]);
  await workContract.setWhiteList("0xA768267D5b04f0454272664F4166F68CFc447346", ["0x66d1D7757CC93bFcd6514d75e04D17d2dCA789EE"], [false])
  await workContract.setWhiteList("0xfdA074b94B1e6Db7D4BEB45058EC99b262e813A5", ["0x66d1D7757CC93bFcd6514d75e04D17d2dCA789EE"], [true])
  console.log(123);
}

async function addNewUser(work, pop721, gp) {
  let workContract = await hre.ethers.getContractAt("UniswapV3WorkCenter", work);
  let popContract = await hre.ethers.getContractAt("Pop721", pop721);

  let tokenId = Math.floor(Math.random() * 1000000);
  await popContract.mint(gp, tokenId);

  await workContract.setQuota(gp, [DAI, UNI, USDC, WETH9, ], 
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000")]);

  for(let token of [DAI, UNI, USDC, WETH9]) {
      let tokenContract = await hre.ethers.getContractAt("Token", token);
      let decimal = await tokenContract.decimals();
      await tokenContract.transfer(gp, toTokenAmount("100000", decimal));
      await tokenContract.transfer(gp, toTokenAmount("100000", decimal));
      console.log("transfer", gp, token);
    }
}

// async function 

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
addQuota("0x95c72417F57dF505B71DB28c79e3D3d9b3bA4187")
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


async function switchUser(bank = "0x7f390bD2E8c5694643bEDC06c2E5e5675c0114f6") {
  let workContract = await hre.ethers.getContractAt("MulBank", bank);
  await workContract.switchWhiteList(["0xA768267D5b04f0454272664F4166F68CFc447346"], [false])
}

// switchUser().then();
// addRemain("0x61E1AE7C9E4fc5Cc86c5257d96B966cf6a0D0616").then();

// switchPool().then();

// addNewUser("0x8b5402184eD7b61ec517b1583E2741efcb9E8b07",
//  "0x2bdC0Ec75873282517C259a7B006D88F8C475879", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0").then(() => {
//    console.log("complete");
//  })
  // switchPool().then()

// addQuota().then();
