import { Fixture } from "ethereum-waffle";
import { utils, Wallet, constants } from "ethers";
import { ethers, waffle } from "hardhat";
import { abi as JoeFactoryAbi, bytecode as JoeFactoryBytecode } from "./contracts/JoeFactory.json";
import { abi as JoeRouterAbi, bytecode as JoeRouterBytecode } from "./contracts/JoeRouter02.json";
import { IJoeFactory, IJoeRouter02, NODERewardManagement, USDC, WAVAX, ZeroXBlocksV1 } from "../typechain";

describe("0xB", () => {
  let wallets: Wallet[], deployer: Wallet, distributePool: Wallet;
  let wavax: WAVAX;
  let joeRouter: IJoeRouter02;
  let zeroXBlocks: ZeroXBlocksV1;
  let nodeRewardManagement: NODERewardManagement;
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

  const nodeRewardManagementFixture: Fixture<{ nodeRewardManagement: NODERewardManagement }> = async () => {
    const NODERewardManagement = await ethers.getContractFactory("NODERewardManagement");
    const nodePrices = [
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
    const nodeRewardManagement = (await NODERewardManagement.deploy(
      nodePrices,
      rewardAPRs,
      cashoutTimeout,
      30000000,
    )) as NODERewardManagement;
    return { nodeRewardManagement };
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
    nodeRewardManagement: NODERewardManagement;
    joeRouter: IJoeRouter02;
    zeroXBlocks: ZeroXBlocksV1;
    usdc: USDC;
  }> = async (wallets, provider) => {
    const { wavax, joeRouter, usdc } = await traderJoeFixture(wallets, provider);
    const { nodeRewardManagement } = await nodeRewardManagementFixture(wallets, provider);

    const ZeroXBlocksV1 = await ethers.getContractFactory("ZeroXBlocksV1");
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
    const zeroXBlocks = (await ZeroXBlocksV1.deploy(
      payees,
      shares,
      addresses,
      balances,
      fees,
      uniV2Router,
      usdc.address,
    )) as ZeroXBlocksV1;

    await nodeRewardManagement.setToken(zeroXBlocks.address);
    await zeroXBlocks.setNodeManagement(nodeRewardManagement.address);

    // wavax - zeroX pair
    await wavax.deposit({ value: utils.parseEther("10") });
    await wavax.approve(joeRouter.address, constants.MaxUint256);
    await zeroXBlocks.approve(joeRouter.address, constants.MaxUint256);
    await joeRouter.addLiquidity(
      zeroXBlocks.address,
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

    return { wavax, nodeRewardManagement, joeRouter, zeroXBlocks, usdc };
  };

  beforeEach("deploy", async () => {
    ({ wavax, nodeRewardManagement, joeRouter, zeroXBlocks, usdc } = await loadFixture(completeFixture));
  });

  describe("First Blood", () => {
    it("mintNodes", async () => {
      await zeroXBlocks.transfer(wallets[2].address, utils.parseEther("1000"));

      await zeroXBlocks.connect(wallets[2]).mintNodes(["test"], 2);
      await zeroXBlocks.connect(wallets[2]).mintNodes(["test2"], 2);
    });
  });
});
