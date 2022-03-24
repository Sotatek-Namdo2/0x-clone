import { utils } from "ethers";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const contPrices = [
    utils.parseEther("5"), // Square
    utils.parseEther("15"), // Cube
    utils.parseEther("30"), // Tesseract
  ];

  const rewardAPRs = [
    250_000_000, // Square
    400_000_000, // Cube
    500_000_000, // Tesseract
  ];
  const autoReduceAPRRate = 30_000_000;
  const cashoutTimeout = 1;
  await deploy("CONTRewardManagement", {
    from: deployer,
    proxy: {
      owner: deployer,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [contPrices, rewardAPRs, cashoutTimeout, autoReduceAPRRate],
        },
      },
    },
    log: true,
  });
};

func.tags = ["Cont"];
export default func;
