import { expect, use } from "chai";
import { Contract, ethers, BigNumber, constants, utils } from "ethers";
import { deployContract, MockProvider, solidity } from "ethereum-waffle";

import { BigNumber as BN } from "bignumber.js";

import Unitroller from "../build_cache/Unitroller.json";
import Comptroller from "../build_cache/Comptroller.json";
import WhitePaperInterestRateModel from "../build_cache/WhitePaperInterestRateModel.json";
import CEther from "../build_cache/CEther.json";
import CErc20Delegator from "../build_cache/CErc20Delegator.json";
import CErc20Delegate from "../build_cache/CErc20Delegate.json";
import Token from "../build_cache/Token.json";
import MulBank from "../build/MulBank.json";

use(solidity);

function convertBigNumber(bnAmount: any, divider: number) {
  return new BN(bnAmount.toString()).dividedBy(new BN(divider)).toFixed();
}
function toTokenAmount(amount: string, decimals: number) {
  return new BN(amount).multipliedBy(new BN("10").pow(decimals)).toFixed();
}

let address0 = "0x0000000000000000000000000000000000000000";

describe("Test Comp", () => {
  let provider = new MockProvider({ ganacheOptions: { gasLimit: 8000000 } });
  const [deployer, wallet1, wallet2, wallet3, wallet4] = provider.getWallets();

  let tx: any;
  let receipt: any;

  async function getBlockNumber() {
    const blockNumber = await provider.getBlockNumber();
    console.log("Current block number: " + blockNumber);
    return blockNumber;
  }

  async function mineBlock(
    provider: MockProvider,
    count: number
  ): Promise<void> {
    console.log("wait mine block count " + count);
    for (let i = 0; i < count; i++) {
      await provider.send("evm_mine", [
        parseInt((Date.now() / 1000).toString()),
      ]);
    }
  }

  let unitroller: Contract;
  let comptroller: Contract;
  let whitePaperInterestRateModel: Contract;
  let cEther: Contract;
  let cErc20: Contract;
  let cErc20Delegator: Contract;
  let daiToken: Contract;
  let mulBank: Contract;

  let MAXIMUM_U256 =
    "115792089237316195423570985008687907853269984665640564039457584007913129639935";

  beforeEach(async () => {
    // unitroller = await deployContract(wallet1, Unitroller);
    comptroller = await deployContract(wallet1, Comptroller);

    daiToken = await deployContract(wallet1, Token, [
      "DAI",
      "DAI",
      18,
      1000000,
    ]);

    console.log("isComptroller", await comptroller.isComptroller());

    whitePaperInterestRateModel = await deployContract(
      wallet1,
      WhitePaperInterestRateModel,
      ["0", "200000000000000000"]
    );

    cEther = await deployContract(wallet1, CEther, [
      comptroller.address,
      whitePaperInterestRateModel.address,
      "200000000000000000000000000",
      "Compound Ether",
      "cETH",
      "8",
      wallet1.address,
    ]);
    mulBank = await deployContract(wallet1, MulBank, []);

    await comptroller._supportMarket(cEther.address);
    cErc20 = await deployContract(wallet1, CErc20Delegate);
    cErc20Delegator = await deployContract(wallet1, CErc20Delegator, [
      daiToken.address,
      comptroller.address,
      whitePaperInterestRateModel.address,
      "200000000000000000000000000",
      "Compound DAI",
      "cDai",
      "8",
      wallet1.address,
      cErc20.address,
      "0x00",
    ]);

    await comptroller._supportMarket(cErc20Delegator.address);

    await daiToken
      .connect(wallet1)
      .approve(cErc20Delegator.address, MAXIMUM_U256);

    await daiToken.mint(wallet2.address, ethers.utils.parseEther("100000000"));

    await daiToken
      .connect(wallet2)
      .approve(cErc20Delegator.address, MAXIMUM_U256);
    await cErc20Delegator
      .connect(wallet2)
      .mint(ethers.utils.parseEther("100000000"));

    await wallet2.sendTransaction({
      to: cEther.address,
      value: ethers.utils.parseEther("100"),
    });

    await mulBank.initPool(daiToken.address);

    await mulBank.initCompound(
      daiToken.address,
      cErc20Delegator.address,
      false
    );
    await daiToken
    .connect(wallet1)
    .approve(mulBank.address, MAXIMUM_U256);
  });

  it("eth", async () => {
    await wallet1.sendTransaction({
      to: cEther.address,
      value: ethers.utils.parseEther("1.0"),
    });
    let cToken = (await cEther.balanceOf(wallet1.address)).toString();
    console.log(cToken);
    console.log(
      "ETH Before",
      ethers.utils.formatEther(await provider.getBalance(wallet1.address)),
      (await cEther.balanceOf(wallet1.address)).toString()
    );
    await cEther.redeem(cToken);
    console.log(
      "ETH After",
      ethers.utils.formatEther(await provider.getBalance(wallet1.address)),
      (await cEther.balanceOf(wallet1.address)).toString()
    );
    await wallet1.sendTransaction({
      to: cEther.address,
      value: ethers.utils.parseEther("1.0"),
    });
    console.log(
      "ETH Before",
      ethers.utils.formatEther(await provider.getBalance(wallet1.address)),
      (await cEther.balanceOf(wallet1.address)).toString()
    );
    await cEther.redeemUnderlying(ethers.utils.parseEther("1.0"));
    console.log(
      "ETH After",
      ethers.utils.formatEther(await provider.getBalance(wallet1.address)),
      (await cEther.balanceOf(wallet1.address)).toString()
    );
  });

  it("cErc20", async () => {
    await cErc20Delegator.mint(ethers.utils.parseEther("1.0"));
    let cToken = (await cErc20Delegator.balanceOf(wallet1.address)).toString();
    console.log(cToken);
    console.log(
      "DAI Before",
      ethers.utils.formatEther(await daiToken.balanceOf(wallet1.address)),
      ethers.utils.formatEther(
        await daiToken.balanceOf(cErc20Delegator.address)
      ),
      ethers.utils.formatEther(await daiToken.balanceOf(cErc20.address)),
      (await cErc20Delegator.balanceOf(wallet1.address)).toString()
    );
    await cErc20Delegator.redeem(cToken);
    console.log(
      "DAI After",
      ethers.utils.formatEther(await daiToken.balanceOf(wallet1.address)),
      (await cErc20Delegator.balanceOf(wallet1.address)).toString()
    );
    await cErc20Delegator.mint(ethers.utils.parseEther("1.0"));
    console.log(
      "DAI Before",
      ethers.utils.formatEther(await daiToken.balanceOf(wallet1.address)),
      (await cErc20Delegator.balanceOf(wallet1.address)).toString()
    );
    await cErc20Delegator.redeemUnderlying(ethers.utils.parseEther("1.0"));
    console.log(
      "DAI After",
      ethers.utils.formatEther(await daiToken.balanceOf(wallet1.address)),
      (await cErc20Delegator.balanceOf(wallet1.address)).toString()
    );

    await mulBank.deposit(daiToken.address, ethers.utils.parseEther("1.0"));

    console.log(
      ethers.utils.formatEther(await daiToken.balanceOf(mulBank.address)),
      (await cErc20Delegator.balanceOf(mulBank.address)).toString(),
    );

    await mulBank.harvestCompound(daiToken.address);
    console.log(
      ethers.utils.formatEther(await daiToken.balanceOf(mulBank.address)),
      (await cErc20Delegator.balanceOf(mulBank.address)).toString(),
    );


    await mulBank.withdraw(daiToken.address, ethers.utils.parseEther("1.0"));
    console.log(
      ethers.utils.formatEther(await daiToken.balanceOf(mulBank.address)),
      (await cErc20Delegator.balanceOf(mulBank.address)).toString(),
    );
  });
});
