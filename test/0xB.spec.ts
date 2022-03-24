import { Fixture } from "ethereum-waffle";
import { utils, Wallet, constants } from "ethers";
import { ethers, waffle } from "hardhat";
import { abi as JoeFactoryAbi, bytecode as JoeFactoryBytecode } from "./contracts/JoeFactory.json";
import { abi as JoeRouterAbi, bytecode as JoeRouterBytecode } from "./contracts/JoeRouter02.json";
import { IJoeFactory, IJoeRouter02, CONTRewardManagement, USDC, WAVAX, ZeroXBlock } from "../typechain";

describe("0xB", () => {
  let wallets: Wallet[], deployer: Wallet, distributePool: Wallet;
  let wavax: WAVAX;
  let joeRouter: IJoeRouter02;
  let zeroXBlock: ZeroXBlock;
  let contRewardManagement: CONTRewardManagement;
  let usdc: USDC, usdcDecimal: number;
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  before("create fixture loader", async () => {
    wallets = await (ethers as any).getSigners();
    [deployer, distributePool] = wallets;
    loadFixture = waffle.createFixtureLoader([deployer as any]);
  });

  const tokenFixture: Fixture<{ wavax: WAVAX; usdc: USDC }> = async () => {
    const WAVAX = await ethers.getContractFactory("WAVAX");
    const USDC = await ethers.getContractFactory("USDC");
    const wavax = (await WAVAX.deploy()) as WAVAX;
    const usdc = (await USDC.deploy()) as USDC;
    usdcDecimal = await usdc.decimals();
    return { wavax, usdc };
  };

  const contRewardManagementFixture: Fixture<{ contRewardManagement: CONTRewardManagement }> = async () => {
    const CONTRewardManagement = await ethers.getContractFactory("CONTRewardManagement");
    const contPrices = [
      utils.parseEther("5"), // Square
      utils.parseEther("15"), // Cube
      utils.parseEther("30"), // Tesseract
    ];
    const rewardAPRs = [
      250000000, // Square
      400000000, // Cube
      500000000, // Tesseract
    ];
    const cashoutTimeout = 1;
    const contRewardManagement = (await CONTRewardManagement.deploy()) as CONTRewardManagement;
    await contRewardManagement.initialize(contPrices, rewardAPRs, cashoutTimeout, 30000000);
    return { contRewardManagement };
  };

  const traderJoeFixture: Fixture<{
    wavax: WAVAX;
    joeFactory: IJoeFactory;
    joeRouter: IJoeRouter02;
    usdc: USDC;
  }> = async ([wallet], provider) => {
    const { wavax, usdc } = await tokenFixture([wallet], provider);

    const joeFactory = (await waffle.deployContract(
      wallet as any,
      {
        bytecode: JoeFactoryBytecode,
        abi: JoeFactoryAbi,
      },
      [wallet.address],
    )) as IJoeFactory;

    const joeRouter = (await waffle.deployContract(
      wallet as any,
      {
        bytecode: JoeRouterBytecode,
        abi: JoeRouterAbi,
      },
      [joeFactory.address, wavax.address],
    )) as IJoeRouter02;

    return { wavax, joeFactory, joeRouter, usdc };
  };

  const completeFixture: Fixture<{
    wavax: WAVAX;
    contRewardManagement: CONTRewardManagement;
    joeRouter: IJoeRouter02;
    zeroXBlock: ZeroXBlock;
    usdc: USDC;
  }> = async (wallets, provider) => {
    const { wavax, joeRouter, usdc } = await traderJoeFixture(wallets, provider);
    const { contRewardManagement } = await contRewardManagementFixture(wallets, provider);

    const ZeroXBlock = await ethers.getContractFactory("ZeroXBlock");
    const deployerAddress = deployer.address;
    const payees = [deployerAddress];
    const shares = [1];
    const addresses = [
      deployerAddress,
      deployerAddress,
      deployerAddress,
      distributePool.address,
      distributePool.address,
      "0x000000000000000000000000000000000000dead",
    ];
    const balances = [800000, 50000, 50000, 50000, 50000, 12345];
    const futureFee = 2;
    const rewardsFee = 60;
    const liquidityPoolFee = 10;
    const cashoutFee = 10;
    const rwSwap = 30;
    const fees = [futureFee, rewardsFee, liquidityPoolFee, cashoutFee, rwSwap];
    const uniV2Router = joeRouter.address;
    const zeroXBlock = (await ZeroXBlock.deploy()) as ZeroXBlock;
    await zeroXBlock.initialize(payees, shares, addresses, balances, fees, usdc.address);

    await contRewardManagement.setToken(zeroXBlock.address);
    await zeroXBlock.setContManagement(contRewardManagement.address);

    // wavax - zeroX pair
    await wavax.deposit({ value: utils.parseEther("10") });
    await wavax.approve(joeRouter.address, constants.MaxUint256);
    await zeroXBlock.approve(joeRouter.address, constants.MaxUint256);
    await joeRouter.addLiquidity(
      zeroXBlock.address,
      wavax.address,
      utils.parseEther("100"),
      utils.parseEther("1"),
      0,
      0,
      deployer.address,
      Math.floor(Date.now() / 1000) + 86400,
    );

    // wavax - usdc pair
    await wavax.deposit({ value: utils.parseEther("10") });
    await usdc.approve(joeRouter.address, constants.MaxUint256);
    await joeRouter.addLiquidity(
      usdc.address,
      wavax.address,
      utils.parseUnits("100", usdcDecimal),
      utils.parseEther("1"),
      0,
      0,
      deployer.address,
      Math.floor(Date.now() / 1000) + 86400,
    );

    return { wavax, contRewardManagement, joeRouter, zeroXBlock, usdc };
  };

  beforeEach("deploy", async () => {
    ({ wavax, contRewardManagement, joeRouter, zeroXBlock, usdc } = await loadFixture(completeFixture));
  });

  describe("First Blood", () => {
    it("mintConts", async () => {
      await zeroXBlock.transfer(wallets[2].address, utils.parseEther("1000"));

      await zeroXBlock.connect(wallets[2]).mintConts(["test"], 2);
      await zeroXBlock.connect(wallets[2]).mintConts(["test2"], 2);
    });
  });
});
