import { utils, Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import { NODERewardManagement, WAVAX, ZeroXBlocksV1, ZeroXBlocksV1__factory } from "../typechain";

describe("0xB", () => {
  let wavax: WAVAX;
  let nodeRewardManagement: NODERewardManagement;
  let deployer: Wallet, distributePool: Wallet;
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  before("create fixture loader", async () => {
    [deployer, distributePool] = await (ethers as any).getSigners();
    loadFixture = waffle.createFixtureLoader([deployer as any]);
  });

  const fixture = async () => {
    const WAVAX = await ethers.getContractFactory("WAVAX");
    const wavax = (await WAVAX.deploy()) as WAVAX;

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

    const ZeroXBlocksV1 = await ethers.getContractFactory("ZeroXBlocksV1");
    const deployAddress = deployer.address;
    const payees = [deployAddress];
    const shares = [1];
    const addresses = [
      deployAddress,
      deployAddress,
      deployAddress,
      deployAddress,
      distributePool.address,
      distributePool.address,
      deployAddress,
      "0x000000000000000000000000000000000000dead",
    ];
    const balances = [500000, 500000, 500000, 500000, 100000, 100000, 100000, 19456743];
    const futureFee = 2;
    const rewardsFee = 60;
    const liquidityPoolFee = 10;
    const cashoutFee = 10;
    const rwSwap = 30;
    const fees = [futureFee, rewardsFee, liquidityPoolFee, cashoutFee, rwSwap];
    const swapAmount = 30;
    const uniV2Router = "0x5db0735cf88f85e78ed742215090c465979b5006";
    const zeroXBlocksV1 = (await ZeroXBlocksV1.deploy(
      payees,
      shares,
      addresses,
      balances,
      fees,
      swapAmount,
      uniV2Router,
    )) as ZeroXBlocksV1;

    return { wavax, nodeRewardManagement, zeroXBlocksV1 };
  };

  beforeEach("deploy LiquidityMathTest", async () => {
    ({ wavax, nodeRewardManagement } = await loadFixture(fixture));
  });

  describe("#addDelta", () => {
    it("1 + 0", async () => {
      console.log(wavax.address);
    });
  });
});
