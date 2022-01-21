import { Fixture } from "ethereum-waffle";
import { utils, Wallet, constants } from "ethers";
import { ethers, waffle } from "hardhat";
import { abi as JoeFactoryAbi, bytecode as JoeFactoryBytecode } from "./contracts/JoeFactory.json";
import { abi as JoeRouterAbi, bytecode as JoeRouterBytecode } from "./contracts/JoeRouter02.json";
import { IJoeFactory, IJoeRouter02, NODERewardManagement, WAVAX, ZeroXBlocksV1 } from "../typechain";

describe("0xB", () => {
  let wallets: Wallet[], deployer: Wallet, distributePool: Wallet;
  let wavax: WAVAX;
  let joeRouter: IJoeRouter02;
  let zeroXBlocks: ZeroXBlocksV1;
  let nodeRewardManagement: NODERewardManagement;
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  before("create fixture loader", async () => {
    wallets = await (ethers as any).getSigners();
    [deployer, distributePool] = wallets;
    loadFixture = waffle.createFixtureLoader([deployer as any]);
  });

  const wavaxFixture: Fixture<{ wavax: WAVAX }> = async () => {
    const WAVAX = await ethers.getContractFactory("WAVAX");
    const wavax = (await WAVAX.deploy()) as WAVAX;
    return { wavax };
  };

  const nodeRewardManagementFixture: Fixture<{ nodeRewardManagement: NODERewardManagement }> = async () => {
    const NODERewardManagement = await ethers.getContractFactory("NODERewardManagement");
    const nodePrices = [
      utils.parseEther("5"), // Square
      utils.parseEther("10"), // Cube
      utils.parseEther("30"), // Tesseract
    ];
    const rewardAPYs = [
      25000000000000, // Square
      40000000000000, // Cube
      50000000000000, // Tesseract
    ];
    const claimTime = 1;
    const nodeRewardManagement = (await NODERewardManagement.deploy(
      nodePrices,
      rewardAPYs,
      claimTime,
    )) as NODERewardManagement;
    return { nodeRewardManagement };
  };

  const traderJoeFixture: Fixture<{ wavax: WAVAX; joeFactory: IJoeFactory; joeRouter: IJoeRouter02 }> = async (
    [wallet],
    provider,
  ) => {
    const { wavax } = await wavaxFixture([wallet], provider);

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

    return { wavax, joeFactory, joeRouter };
  };

  const completeFixture: Fixture<{
    wavax: WAVAX;
    nodeRewardManagement: NODERewardManagement;
    joeRouter: IJoeRouter02;
    zeroXBlocks: ZeroXBlocksV1;
  }> = async (wallets, provider) => {
    const { wavax, joeRouter } = await traderJoeFixture(wallets, provider);
    const { nodeRewardManagement } = await nodeRewardManagementFixture(wallets, provider);

    const ZeroXBlocksV1 = await ethers.getContractFactory("ZeroXBlocksV1");
    const deployerAddress = deployer.address;
    const payees = [deployerAddress];
    const shares = [1];
    const addresses = [
      deployerAddress,
      deployerAddress,
      deployerAddress,
      deployerAddress,
      distributePool.address,
      distributePool.address,
      deployerAddress,
      "0x000000000000000000000000000000000000dead",
    ];
    const balances = [220000, 220000, 220000, 220000, 10000, 100000, 10000, 19456743];
    const futureFee = 2;
    const rewardsFee = 60;
    const liquidityPoolFee = 10;
    const cashoutFee = 10;
    const rwSwap = 30;
    const fees = [futureFee, rewardsFee, liquidityPoolFee, cashoutFee, rwSwap];
    const swapAmount = 30;
    const uniV2Router = joeRouter.address;
    const zeroXBlocks = (await ZeroXBlocksV1.deploy(
      payees,
      shares,
      addresses,
      balances,
      fees,
      swapAmount,
      uniV2Router,
    )) as ZeroXBlocksV1;

    await nodeRewardManagement.setToken(zeroXBlocks.address);
    await zeroXBlocks.setNodeManagement(nodeRewardManagement.address);

    await wavax.deposit({ value: utils.parseEther("10") });
    await wavax.approve(joeRouter.address, constants.MaxUint256);
    await zeroXBlocks.approve(joeRouter.address, constants.MaxUint256);
    // await joeRouter.addLiquidity(
    //   zeroXBlocks.address,
    //   wavax.address,
    //   utils.parseEther("1"),
    //   utils.parseEther("1"),
    //   0,
    //   0,
    //   deployer.address,
    //   Math.floor(Date.now() / 1000) + 86400,
    // );

    return { wavax, nodeRewardManagement, joeRouter, zeroXBlocks };
  };

  beforeEach("deploy", async () => {
    ({ wavax, nodeRewardManagement, joeRouter, zeroXBlocks } = await loadFixture(completeFixture));
  });

  describe("First Blood", () => {
    it("createNodeWithTokens", async () => {
      await zeroXBlocks.transfer(wallets[2].address, utils.parseEther("1000"));

      await zeroXBlocks.connect(wallets[2]).createNodeWithTokens("test", 2);
      // await zeroXBlocks.connect(wallets[2]).createNodeWithTokens("test2", 2);
    });
  });
});
