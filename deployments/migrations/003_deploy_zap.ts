import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment): Promise<void> {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const usdcToken = process.env.USDC_TOKEN_ADDRESS;
  const usdtToken = process.env.USDC_TOKEN_ADDRESS || process.env.USDC_TOKEN_ADDRESS;
  const wrappedNative = process.env.WRAPPED_NATIVE;
  const OxBlockToken = process.env.OXBLOCK_TOKEN_ADDRESS;

  await deploy("Zap", {
    from: deployer,
    proxy: {
      owner: deployer,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [usdtToken, wrappedNative, usdcToken],
        },
      },
    },
    log: true,
  });

  await deploy("Zap", {
    from: deployer,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [
          usdtToken, //usdt
          wrappedNative, // wrap native token
          usdcToken, // usdc
          OxBlockToken, // 0block
        ],
      },
    },
  });
};

func.tags = ["Zap"];
export default func;
