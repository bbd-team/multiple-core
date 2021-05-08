import { Contract, ethers, BigNumber } from "ethers";
import { BigNumber as BN } from "bignumber.js";


import MulBank from "../build/MulBank.json";
import ERC20 from "../build/ERC20.json";
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

let daiToken: any = "0x0540C4042F58656859D8093459D43c414b33a4B7";
let mulBank: any = "0x8C4FaF376c80302437227521CD2435082935a313";




async function init() {
  daiToken = new Contract(daiToken, ERC20.abi, provider).connect(wallet1);
  mulBank = new Contract(mulBank, MulBank.abi, provider).connect(wallet1);
}

async function deploy() {
  daiToken = await deployContract(wallet1, Token,["DAI","DAI",18,100000000000]);
  console.log('let daiToken: any = "' + daiToken.address + '"');
  mulBank = await deployContract(wallet1, MulBank);
  console.log('let mulBank: any = "' + mulBank.address + '"');
  await (await mulBank.initPool(daiToken.address)).wait();
}

(async function() {
  await init()
  await deploy();
})();
