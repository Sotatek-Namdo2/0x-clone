import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { chainIds } from "../../hardhat.config";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts, getChainId } = hre;
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (chainId === chainIds.avax.toString()) {
    return;
  }

  const payees = [deployer];
  const shares = [1];
  const addresses = [
    deployer,
    deployer,
    deployer,
    deployer,
    deployer,
    deployer,
    deployer,
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

  await deploy("ZeroXBlocksV1", {
    from: deployer,
    args: [payees, shares, addresses, balances, fees, swapAmount, uniV2Router],
    log: true,
  });

  const NODERewardManagement = await deployments.get("NODERewardManagement");
  const ZeroXBlocksV1 = await deployments.get("ZeroXBlocksV1");
  await execute("NODERewardManagement", { from: deployer, log: true }, "setToken", ZeroXBlocksV1.address);
  await execute("ZeroXBlocksV1", { from: deployer, log: true }, "setNodeManagement", NODERewardManagement.address);
};

func.tags = ["ZeroXBlocks"];
export default func;
