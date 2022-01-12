import { utils } from "ethers";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { chainIds } from "../../hardhat.config";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts, getChainId } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (chainId === chainIds.avax.toString()) {
    return;
  }

  const nodePrice = utils.parseEther("12.5");
  const rewardPerNode = 3833912037037;
  const claimTime = 1;
  await deploy("NODERewardManagement", {
    from: deployer,
    args: [nodePrice, rewardPerNode, claimTime],
    log: true,
  });
};

func.tags = ["Node"];
export default func;
