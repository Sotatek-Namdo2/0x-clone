import { BigNumber } from "ethers";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { chainIds } from "../../hardhat.config";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts, getChainId } = hre;
  const { deploy, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();
  const developmentFund = process.env.DEVELOPMENT_FUND_WALLET || deployer;
  const liquidityPool = process.env.LIQUIDITY_POOL_WALLET || deployer;
  const treasury = process.env.TREASURY_WALLET || deployer;
  const rewards = process.env.REWARDS_WALLET || deployer;
  const reserveRewards = process.env.RESERVE_REWARDS_WALLET || rewards;
  const reserveLiquidityPool = process.env.RESERVE_LIQUIDITY_WALLET || deployer;
  const initialHolders = [deployer, deployer, deployer];

  const payees = [deployer];
  const shares = [1];
  const addresses = [
    deployer,
    developmentFund,
    liquidityPool,
    treasury,
    rewards,
    reserveRewards,
    reserveLiquidityPool,
    initialHolders[0],
    initialHolders[1],
    initialHolders[2],
  ];

  const balances = [0, 98_800, 0, 0, 1000, 699_000, 100_000, 50_000, 50_000, 1_200];
  const devFundFee = 5;
  const treasuryFee = 20;
  const rewardsFee = 55;
  const liquidityPoolFee = 20;
  const cashoutFee = 10;
  const swapFee = 25;
  const fees = [devFundFee, treasuryFee, rewardsFee, liquidityPoolFee, cashoutFee, swapFee];
  const USDCToken = process.env.USDC_TOKEN_ADDRESS;

  await deploy("ZeroXBlock", {
    from: deployer,
    log: true,
    proxy: {
      owner: deployer,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [payees, shares, addresses, balances, fees, USDCToken],
        },
      },
    },
  });

  const CONTRewardManagement = await deployments.get("CONTRewardManagement");
  const LiquidityRouter = await deployments.get("LiquidityRouter");
  const ZeroXBlock = await deployments.get("ZeroXBlock");
  // todo: if address already set then don't call tx
  await execute("CONTRewardManagement", { from: deployer, log: true }, "setToken", ZeroXBlock.address);
  await execute("LiquidityRouter", { from: deployer, log: true }, "setToken", ZeroXBlock.address);
  await execute("Zap", { from: deployer, log: true }, "setToken", ZeroXBlock.address);
  await execute("LPStaking", { from: deployer, log: true }, "setToken", ZeroXBlock.address);
  await execute("ZeroXBlock", { from: deployer, log: true }, "setContManagement", CONTRewardManagement.address);
  await execute("ZeroXBlock", { from: deployer, log: true }, "setLiquidityRouter", LiquidityRouter.address);

  // const poolAddress = await read("LiquidityRouter", "uniswapV2Pair");
  // const poolCount = await read("LPStaking", "pools");
  // const timestamp = new Date().getTime() / 1000;

  // if (poolCount == 0) {
  //   await execute(
  //     "LPStaking",
  //     { from: deployer, log: true },
  //     "addPool",
  //     poolAddress,
  //     BigNumber.from("20000000000000000000"),
  //     timestamp + 300,
  //     86400 * 7
  //   );
  // }
};

func.tags = ["ZeroXBlock"];
export default func;
