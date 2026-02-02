import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.connect();

const [deployer, user1, user2] = await ethers.getSigners();

async function deployStakeFixture() {
    const stake = await ethers.deployContract("Stake", deployer);
    const rewardToken = await ethers.deployContract("SSToken", deployer);
    const stakeToken = await ethers.deployContract("SKToken", deployer);

    await rewardToken.connect(deployer).mint(await stake.getAddress(), ethers.parseEther("10000000000"));
    await stakeToken.connect(deployer).mint(user2.address, ethers.parseEther("100000000"));
    // 获取部署时的区块号
    const deploymentBlockNumber = await ethers.provider.getBlockNumber();
    return { stake, rewardToken, stakeToken, deploymentBlockNumber };
}

async function initPool() {
    const { stake, rewardToken, stakeToken, deploymentBlockNumber } = await networkHelpers.loadFixture(deployStakeFixture);
    await stake.initialize(rewardToken, deploymentBlockNumber, 9999, 100000000);
    await stake.addPool(ethers.ZeroAddress, 10000, ethers.parseEther("1"), 10);
    const ethId = await stake.poolLength() - 1n;
    await stake.addPool(await stakeToken.getAddress(), 1000, ethers.parseEther("1"), 10);
    const tokenId = await stake.poolLength() - 1n;
    return { stake, rewardToken, stakeToken, ethId, tokenId };
}

describe("质押测试", function () {
    it("创建池子", async function () {
        const { stake, ethId, tokenId, stakeToken } = await initPool();
        const ethPool = await stake.poolList(ethId);
        expect(ethPool.tokenAddr).to.equal(ethers.ZeroAddress);
        const tokenPool = await stake.poolList(tokenId);
        expect(tokenPool.tokenAddr).to.equal(await stakeToken.getAddress());
    });
    it("设置区块", async function () {
        const { stake, ethId, tokenId, stakeToken } = await initPool();
        await expect(stake.setStartBlock(1)).to.emit(stake, "SetStartBlockEvent").withArgs(1);
        await expect(stake.setEndBlock(10000)).to.emit(stake, "SetEndBlockEvent").withArgs(10000);
        expect(await stake.startBlock()).to.equal(1);
        expect(await stake.endBlock()).to.equal(10000);
    });
    it("质押", async function () {
        const { stake, ethId, tokenId, stakeToken } = await initPool();
        await stake.connect(user1).stake(ethId, 0n, { value: ethers.parseEther("1") });
        await stakeToken.connect(user2).approve(stake.getAddress(), ethers.parseEther("10000"));
        await stake.connect(user2).stake(tokenId, ethers.parseEther("10000"));

        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 5);
        console.log(await stake.getPendingReward(ethId, user1.address));
        console.log(await stake.getPendingReward(tokenId, user2.address));

        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 5);
        await stake.connect(user1).unstake(ethId, ethers.parseEther("1"));
        console.log(await stake.getPendingReward(ethId, user1.address));
        console.log(await stake.getPendingReward(tokenId, user2.address));
    });
    it("取消质押ETH", async function () {
        const { stake, ethId, tokenId, stakeToken } = await initPool();
        await stake.connect(user1).stake(ethId, 0n, { value: ethers.parseEther("100") });
        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 5);
        const val = ethers.parseEther("50");
        console.log("pendingAmount: " + await stake.getPendingReward(ethId, user1.address));
        console.log("提现前剩余ETH: " + ethers.formatEther(await ethers.provider.getBalance(user1.address)));
        expect(await stake.connect(user1).unstake(ethId, val)).to.emit(stake, "UnstakeEvent").withArgs(ethId, user1.address, val);
        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 15);
        await stake.connect(user1).withdraw(ethId)
        console.log("提现后剩余ETH: " + ethers.formatEther(await ethers.provider.getBalance(user1.address)));
    });
    it("取消质押代币", async function () {
        const { stake, ethId, tokenId, stakeToken } = await initPool();
        await stakeToken.connect(user2).approve(stake.getAddress(), ethers.parseEther("100000"));
        await stake.connect(user2).stake(tokenId, ethers.parseEther("100000"));
        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 5);

        const val = ethers.parseEther("5000");
        console.log("pendingAmount: " + await stake.getPendingReward(tokenId, user2.address));
        console.log("提现前剩余代币: " + ethers.formatEther(await stakeToken.balanceOf(user2.address)));
        expect(await stake.connect(user2).unstake(tokenId, val)).to.emit(stake, "UnstakeEvent").withArgs(tokenId, user2.address, val);
        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 15);
        await stake.connect(user2).withdraw(tokenId)
        console.log("提现后剩余代币: " + ethers.formatEther(await stakeToken.balanceOf(user2.address)));
    });
    it("领取奖励", async function () {
        const { stake, ethId, tokenId, stakeToken, rewardToken } = await initPool();
        await stake.connect(user1).stake(ethId, 0n, { value: ethers.parseEther("10") });
        await networkHelpers.mineUpTo((await ethers.provider.getBlockNumber()) + 50);

        console.log("待领取奖励: ", await stake.getPendingReward(ethId, user1.address));
        console.log("领取前: ", ethers.formatEther(await rewardToken.balanceOf(user1.address)));
        await stake.connect(user1).claim(ethId)
        console.log("领取后: ", ethers.formatEther(await rewardToken.balanceOf(user1.address)));
    });
});