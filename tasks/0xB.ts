import { constants, utils } from "ethers";
import { task } from "hardhat/config";
import { IJoeRouter02__factory, WAVAX__factory, ZeroXBlocksV1__factory } from "../typechain";
import { ADDRESSES_FOR_CHAIN_ID } from "./constant";

task("wavax:deposit", "deposit", async (_taskArgs, hre) => {
  const { ethers, getChainId } = hre;
  const chainId = Number(await getChainId());
  const [deployer] = await ethers.getSigners();
  const wavax = await WAVAX__factory.connect(ADDRESSES_FOR_CHAIN_ID[chainId].WAVAX || "", ethers.provider);

  const amount = utils.parseEther("1");
  const tx = await wavax.connect(deployer).deposit({ value: amount });
  await tx.wait();
  console.log({ tx: tx.hash });
});

task("joe:addLiquidity", "", async (_taskArgs, hre) => {
  const { ethers, deployments, getChainId } = hre;
  const chainId = Number(await getChainId());
  const [deployer] = await ethers.getSigners();
  const ZeroXBlocksV1 = await deployments.get("ZeroXBlocksV1");
  const joeRouter = await IJoeRouter02__factory.connect(
    ADDRESSES_FOR_CHAIN_ID[chainId].JoeRouter || "",
    ethers.provider,
  );
  const tokenAmount = utils.parseEther("1");
  const wavaxAmount = tokenAmount.div(10);
  const deadline = Math.floor(Date.now() / 1000) + 86400;

  const wavax = await WAVAX__factory.connect(ADDRESSES_FOR_CHAIN_ID[chainId].WAVAX || "", ethers.provider);
  const zeroX = await ZeroXBlocksV1__factory.connect(ZeroXBlocksV1.address, ethers.provider);
  await (await wavax.approve(joeRouter.address, constants.MaxUint256)).wait();
  await (await zeroX.approve(joeRouter.address, constants.MaxUint256)).wait();

  const tx = await joeRouter
    .connect(deployer)
    .addLiquidity(
      ZeroXBlocksV1.address,
      ADDRESSES_FOR_CHAIN_ID[chainId].WAVAX || "",
      tokenAmount,
      wavaxAmount,
      0,
      0,
      deployer.address,
      deadline,
    );
  await tx.wait();
  console.log({ tx: tx.hash });
});
