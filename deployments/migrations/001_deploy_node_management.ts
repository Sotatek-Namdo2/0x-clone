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
    250_000_000, // Square
    400_000_000, // Cube
    500_000_000, // Tesseract
  ];
  const autoReduceAPRRate = 3000000000000;
  const claimTime = 180; // 3 minutes
  await deploy("NODERewardManagement", {
    from: deployer,
    args: [nodePrices, rewardAPRs, claimTime, autoReduceAPRRate],
    log: true,
  });
};

func.tags = ["Node"];
export default func;
