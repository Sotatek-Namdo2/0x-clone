import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { chainIds } from "../../hardhat.config";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts, getChainId } = hre;
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const developmentFund = process.env.DEVELOPMENT_FUND_WALLET || deployer;
  const liquidityPool = process.env.LIQUIDITY_POOL_WALLET || deployer;
  const treasury = process.env.TREASURY_WALLET || deployer;
  const rewards = process.env.REWARDS_WALLET || deployer;
  const reserveRewards = process.env.RESERVE_REWARDS_WALLET || rewards;
  const reserveLiquidityPool = process.env.RESERVE_LIQUIDITY_WALLET || deployer;
  const initialHolders = [
    "0x14BC67Cb9c42eA4472227441849CB7891c1775BE",
    "0xF664518d926e252fa1a521fe02a89BF2eaBa7b4A",
    "0xee16fb49501790c42da96dfe54b2e18f3bCfcfB2",
  ];
  const chainId = await getChainId();
  const owner = process.env.ZEROXBLOCKS_OWNER || deployer;

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
  const fees = [devFundFee, treasuryFee, rewardsFee, liquidityPoolFee, cashoutFee];
  const uniV2Router = process.env.UNIV2ROUTER_ADDRESS;
  const USDCToken = process.env.USDC_TOKEN_ADDRESS;

  await deploy("ZeroXBlocksV1", {
    from: deployer,
    log: true,
    proxy: {
      owner: deployer,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [payees, shares, addresses, balances, fees, uniV2Router, USDCToken],
        },
      },
    },
  });

  const CONTRewardManagement = await deployments.get("CONTRewardManagement");
  const ZeroXBlocksV1 = await deployments.get("ZeroXBlocksV1");
  await execute("CONTRewardManagement", { from: deployer, log: true }, "setToken", ZeroXBlocksV1.address);
  await execute("ZeroXBlocksV1", { from: deployer, log: true }, "setContManagement", CONTRewardManagement.address);
  // await execute("CONTRewardManagement", { from: deployer, log: true }, "setAdmin", owner);
  // await execute("ZeroXBlocksV1", { from: deployer, log: true }, "transferOwnership", owner);
};

func.tags = ["ZeroXBlocks"];
export default func;
