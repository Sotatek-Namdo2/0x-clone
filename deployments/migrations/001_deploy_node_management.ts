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

  const nodePriceFine = utils.parseEther("12.5");
  const nodePriceMean = utils.parseEther("25");
  const nodePriceFinest = utils.parseEther("37.5");
  const rewardPerNodeFine = 3833912037037;
  const rewardPerNodeMean = 3833912037037 * 2;
  const rewardPerNodeFinest = 3833912037037 * 3;
  const claimTime = 1;
  await deploy("NODERewardManagement", {
    from: deployer,
    args: [
      nodePriceFine,
      nodePriceMean,
      nodePriceFinest,
      rewardPerNodeFine,
      rewardPerNodeMean,
      rewardPerNodeFinest,
      claimTime,
    ],
    log: true,
  });
};

func.tags = ["Node"];
export default func;
