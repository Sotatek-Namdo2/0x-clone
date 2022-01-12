import { utils } from "ethers";
import { task } from "hardhat/config";
import { IWAVAX__factory } from "../typechain";

task("wavax:deposit", "deposit", async (_taskArgs, hre) => {
  const { ethers } = hre;
  const [deployer] = await ethers.getSigners();
  const wavax = await IWAVAX__factory.connect("0x1d308089a2d1ced3f1ce36b1fcaf815b07217be3", ethers.provider);

  const amount = utils.parseEther("0.01");
  const tx = await wavax.connect(deployer).deposit({ value: amount });
  await tx.wait();
  console.log(tx.hash);
});
