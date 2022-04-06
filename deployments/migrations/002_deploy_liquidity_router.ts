import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const uniV2Router = process.env.UNIV2ROUTER_ADDRESS;
  const swapTaxPool = process.env.DEVELOPMENT_FUND_WALLET;
  const swapTaxFee = 100_000;

  await deploy("LiquidityRouter", {
    from: deployer,
    proxy: {
      owner: deployer,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [uniV2Router, swapTaxFee, swapTaxPool],
        },
      },
    },
    log: true,
  });
};

func.tags = ["LiqRouter"];
export default func;
