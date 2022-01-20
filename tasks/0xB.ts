import { utils } from "ethers";
import { task } from "hardhat/config";
import { IJoeRouter02__factory, IWAVAX__factory } from "../typechain";

task("wavax:deposit", "deposit", async (_taskArgs, hre) => {
  const { ethers } = hre;
  const [deployer] = await ethers.getSigners();
  const wavax = await IWAVAX__factory.connect("0x1d308089a2d1ced3f1ce36b1fcaf815b07217be3", ethers.provider);

  const amount = utils.parseEther("0.01");
  const tx = await wavax.connect(deployer).deposit({ value: amount });
  await tx.wait();
  console.log(tx.hash);
});

task("joe:addLiquidity", "", async (_taskArgs, hre) => {
  const { ethers, deployments } = hre;
  const [deployer] = await ethers.getSigners();
  const ZeroXBlocksV1 = await deployments.get("ZeroXBlocksV1");
  const joeRouter = await IJoeRouter02__factory.connect("0x5db0735cf88f85e78ed742215090c465979b5006", ethers.provider);
  const tokenAmount = utils.parseEther("1");
  const wavaxAmount = tokenAmount.div(10);
  const deadline = Math.floor(Date.now() / 1000) + 86400;

  const tx = await joeRouter
    .connect(deployer)
    .addLiquidity(
      ZeroXBlocksV1.address,
      "0xd00ae08403B9bbb9124bB305C09058E32C39A48c",
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
