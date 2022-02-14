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

  const nodePrices = [
    utils.parseEther("5"), // Square
    utils.parseEther("15"), // Cube
    utils.parseEther("30"), // Tesseract
  ];

  const rewardAPRs = [
    25000000000000, // Square
    40000000000000, // Cube
    50000000000000, // Tesseract
  ];
  const claimTime = 180; // 3 minutes
  await deploy("NODERewardManagement", {
    from: deployer,
    args: [nodePrices, rewardAPRs, claimTime],
    log: true,
  });
};

func.tags = ["Node"];
export default func;
