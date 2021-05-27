import { Contract, ethers, BigNumber } from "ethers";
import { BigNumber as BN } from "bignumber.js";


import MulBank from "../build/MulBank.json";
import UniswapV3Strategy from "../build/UniswapV3Strategy.json";
import MulWork from "../build/MulWork.json";
import ERC20 from "../build/ERC20.json";
import Sandbox from "../build/Sandbox.json";

import CErc20 from "../build_cache/CErc20.json";
import CEther from "../build_cache/CEther.json";
import Token from "../build_cache/Token.json";

const sleep = (ms: number) =>
  new Promise((resolve) =>
    setTimeout(() => {
      resolve(1);
    }, ms)
  );
async function waitForMint(tx: string) {
  // console.log("tx:", tx);
  let result = null;
  do {
    result = await provider.getTransactionReceipt(tx);
    await sleep(500);
  } while (result === null);
  await sleep(500);
}

async function deployContract(signer: any, contractJSON: any, args?: any[]) {
  let factory = new ethers.ContractFactory(
    contractJSON.abi,
    contractJSON.bytecode,
    signer
  );
  if (!args) args = [];
  let ins = await factory.deploy(...args, {
    gasPrice: ethers.utils.parseUnits("10", "gwei"),
  });
  await waitForMint(ins.deployTransaction.hash);
  return ins;
}

export class FryerDetail {
  name: string;
  token: any;
  oven: any;
  fryer: any;
  fryerConfig: any;
  yearnVaultAdapter: any;
  yearnControllerMock: any;
  yearnVaultMock: any;

  constructor(name_: string) {
    this.name = name_;
  }
}

let address0 = "0x0000000000000000000000000000000000000000";

let provider = new ethers.providers.JsonRpcProvider(
  "https://rinkeby.infura.io/v3/81c2db57647c4412b8ffb98058b5708d" // TODO RPC URL
);

const [wallet1] = Array(7)
  .fill("66fea855f0d990b7c3b42bddf1ca0e35d4211c1f85724e309f94201e7ed38e99") // TODO PRIVATE kEY
  .map((x: string) => new ethers.Wallet(x, provider));

let weekTimestamp = 60 * 60 * 24 * 7;

let usdc: any = "0xd5B61730D852780c0E0D2cb04cAdEF7498ab0fab";
let eth: any = "0x794aa9dDEF81Fcb4AE1e5bd0eD3664D982C77183";
let mulBank: any = "0x1555a04b203Cd5C7678C509A9d2060A402287ade";
let strategy: any = "0x574EC9338d242c44B05Ca3787A15Cca89069711f";
let mulWork: any = "0x496854685Cd191f8725CbAe6baC99D8B9BfEeE80";
let sandbox: any = "0x82219B2B463502935Cf74C47B8844C1E0B0a0D6D";
let uniFactory: any = "0x1f98431c8ad98523631ae4a59f267346ea31f984";
let reward: any = "0x2D83750BDB3139eed1F76952dB472A512685E3e0";


// async function init() {
//   daiToken = new Contract(daiToken, ERC20.abi, provider).connect(wallet1);
//   mulBank = new Contract(mulBank, MulBank.abi, provider).connect(wallet1);
// }

function toTokenAmount(amount: string, decimals: number = 18) {
    return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed()
}

async function deploy() {
  // usdc = await deployContract(wallet1, Token,["USDC","USDC",6,100000000000]);
  // usdc = usdc.address;
  // // console.log('let usdt: any = "' + usdt.address + '"');
  // eth = await deployContract(wallet1, Token,["ETH","ETH",18,100000000000]);
  // eth = eth.address;
  // console.log('let daiToken: any = "' + btc.address + '"');  
  mulBank = await deployContract(wallet1, MulBank);
  mulWork = await deployContract(wallet1, MulWork, [address0, address0, mulBank.address]);
  console.log("deploy");
  await (await mulBank.initPool(usdc)).wait();
  await (await mulBank.initPool(eth)).wait();

  strategy = await deployContract(wallet1, UniswapV3Strategy, [uniFactory, mulWork.address, mulBank.address, reward]);
  console.log("set strategy");

  await (await mulBank.addPermission(strategy.address)).wait();
  await (await mulWork.addPermission(strategy.address)).wait();

  console.log('let USDC: any = "' + usdc + '"');
  console.log('let ETH: any = "' + eth + '"');
  console.log('let mulBank: any = "' + mulBank.address + '"');
  console.log('let mulWork: any = "' + mulWork.address + '"');
  console.log('let strategy: any = "' + strategy.address + '"');
}

async function deploySandbox() {
  let usdcContract = new Contract(usdc, ERC20.abi, provider).connect(wallet1);
  let ethContract = new Contract(eth, ERC20.abi, provider).connect(wallet1);
  sandbox = await deployContract(wallet1, Sandbox, [uniFactory, eth, usdc]);
  console.log('sandbox deployed');
  await (await usdcContract.connect(wallet1).transfer(sandbox.address, toTokenAmount("1000000", 6))).wait();
  await (await ethContract.connect(wallet1).transfer(sandbox.address, toTokenAmount("1000000"))).wait();
  console.log('let sandbox: any = "' + sandbox.address + '"');
}

(async function() {
  // await init()
  await deploy();
  // await deploySandbox();
})();