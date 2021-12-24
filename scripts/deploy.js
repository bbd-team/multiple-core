// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const uniFactory = "0x80a39Ed431B27F53587eC55331e41DadA01B8e96";
const DAI = "0x17B63a4DDFbA78703A33756D8b93a91D7Bc6a13d";
const UNI = "0x7bfeAf9EE141d06aDc9c85DeB8d3b72117C316CE";
const USDC = "0xb16825b4cD5034Dc0A4fC00e11A4653B07e6C668";
const WETH9 = "0xEAd038CEC675382A1f9e281B2FBdDB970C3f1105";

const bank = "0x12435D6366c3DC367f8E3A0B9fc9E1A603ECFDc1"
const gpList = ["0xA768267D5b04f0454272664F4166F68CFc447346", "0xfdA074b94B1e6Db7D4BEB45058EC99b262e813A5",
 "0xc03C12101AE20B8e763526d6841Ece893248a069", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0", "0x3897A13FbC160036ba614c07D703E1fCbC422599"]

let BN = require("bignumber.js");

let Pop721;
let MulBank;
let MulWork;
let ERC20;
let owner = "0x9F93bF49F2239F414cbAd0e4375c1e0E7AB833a2";


const poolList = ["0x6ae51C31940B678233Ad2F2e1F40adF58B36aCBE",
 "0x0F6d297dD4CDaaC6f5539D4252d0C79aFe881461", "0xbB2d74a5286591C65C0D33D57c3D87726FDC034D",
  "0x1b336682a69eB5AcCb9651C225538d10df10B60C", "0x6b52025D83d47cA9a08dc078f803cf767895c42E"]

function toTokenAmount(amount, decimals = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function addRemain() {
  MulBank = await hre.ethers.getContractFactory("MulBank");
  let bankContract = await hre.ethers.getContractAt("MulBank", bank);
  await (await bankContract.switchWhiteList(gpList, Array(gpList.length).fill(true))).wait();
  // await (await bankContract.addRemains([DAI, UNI, USDC, ETH], 
  //   [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000")])∂∂
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

  // WETH9 = await WETH.deploy();
  const pop721 = await Pop721.deploy("Multiple GP", "GP", "https://www.multiple.fi");
  const mulBank = await MulBank.deploy(WETH9);
  const mulWork = await MulWork.deploy(pop721.address);

  console.log("deploy");
  await (await mulBank.initPoolList([USDC, UNI, WETH9, DAI], [0,0,0,0])).wait();

  const Strategy = await hre.ethers.getContractFactory("UniswapV3Strategy");
  const strategy = await Strategy.deploy(uniFactory, mulWork.address, mulBank.address, owner, owner);

  await (await mulBank.addPermission(strategy.address)).wait();
  await (await mulWork.addPermission(strategy.address)).wait();

  await mulWork.switchPool(poolList, [true,true,true,true,true]);

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
}

async function addQuota(work) {
  let workContract = await hre.ethers.getContractAt("UniswapV3WorkCenter", work.address);

  for(let gp of gpList) {
    await workContract.setQuota(gp, [DAI, UNI, USDC, WETH9], 
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000")]);

    // for(let token of [DAI, UNI, USDC, WETH9]) {
    //   let tokenContract = await hre.ethers.getContractAt("Token", token);
    //   let decimal = await tokenContract.decimals();
    //   await tokenContract.transfer(gp, toTokenAmount("100000", decimal));
    //   console.log("transfer", gp, token);
    // }
    
  }
   console.log("complete");


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

  await workContract.setQuota(gp, [DAI, UNI, USDC, WETH9], 
    [toTokenAmount("10000000"), toTokenAmount("10000000"), toTokenAmount("10000000", 6), toTokenAmount("10000000")]);

  for(let token of [DAI, UNI, USDC, WETH9]) {
      let tokenContract = await hre.ethers.getContractAt("Token", token);
      let decimal = await tokenContract.decimals();
      await tokenContract.transfer(gp, toTokenAmount("100000", decimal));
      console.log("transfer", gp, token);
    }
}

// async function 

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


// switchPool().then();

// addNewUser("0x8b5402184eD7b61ec517b1583E2741efcb9E8b07",
//  "0x2bdC0Ec75873282517C259a7B006D88F8C475879", "0x3c5bae74ecaba2490e23c2c4b65169457c897aa0").then(() => {
//    console.log("complete");
//  })
  // switchPool().then()

// addQuota().then();
