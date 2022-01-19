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

  const nodePriceSquare = utils.parseEther("12.5");
  const nodePriceCube = utils.parseEther("25");
  const nodePriceTeseract = utils.parseEther("37.5");
  const rewardAPYPerNodeSquare = 3833912037037;
  const rewardAPYPerNodeCube = 3833912037037 * 2;
  const rewardAPYPerNodeTeseract = 3833912037037 * 3;
  const claimTime = 1;
  await deploy("NODERewardManagement", {
    from: deployer,
    args: [
      nodePriceSquare,
      nodePriceCube,
      nodePriceTeseract,
      rewardAPYPerNodeSquare,
      rewardAPYPerNodeCube,
      rewardAPYPerNodeTeseract,
      claimTime,
    ],
    log: true,
  });
};

func.tags = ["Node"];
export default func;
