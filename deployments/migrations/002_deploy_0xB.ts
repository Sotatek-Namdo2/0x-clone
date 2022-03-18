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
  const chainId = await getChainId();

  if (chainId === chainIds.avax.toString()) {
    return;
  }

  const payees = [deployer];
  const shares = [1];
  const addresses = [
    deployer,
    developmentFund,
    liquidityPool,
    treasury,
    rewards,
    "0x000000000000000000000000000000000000dead",
  ];

  const balances = [800000, 50000, 50000, 50000, 50000, 12345];
  const futureFee = 10;
  const treasuryFee = 20;
  const rewardsFee = 50;
  const liquidityPoolFee = 20;
  const cashoutFee = 10;
  const fees = [futureFee, treasuryFee, rewardsFee, liquidityPoolFee, cashoutFee];
  const uniV2Router = "0x60aE616a2155Ee3d9A68541Ba4544862310933d4";

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
};

func.tags = ["ZeroXBlocks"];
export default func;
