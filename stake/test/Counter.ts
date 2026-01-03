import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.connect();

// 定义 fixture 函数
async function deployCounterFixture() {
  // 部署合约
  const counter = await ethers.deployContract("Counter");

  // 获取部署时的区块号
  const deploymentBlockNumber = await ethers.provider.getBlockNumber();

  // 返回需要在测试中使用的对象
  return { counter, deploymentBlockNumber };
}

describe("Counter", function () {
  it("Should emit the Increment event when calling the inc() function", async function () {
    const { counter } = await networkHelpers.loadFixture(deployCounterFixture);

    await expect(counter.inc()).to.emit(counter, "Increment").withArgs(1n);
  });

  it("The sum of the Increment events should match the current value", async function () {
    const { counter, deploymentBlockNumber } = await networkHelpers.loadFixture(
      deployCounterFixture
    );

    // run a series of increments
    for (let i = 1; i <= 10; i++) {
      await counter.incBy(i);
    }

    const events = await counter.queryFilter(
      counter.filters.Increment(),
      deploymentBlockNumber,
      "latest"
    );

    // check that the aggregated events match the current value
    let total = 0n;
    for (const event of events) {
      total += event.args.by;
    }

    expect(await counter.x()).to.equal(total);
  });

  it("Should start with value 0", async function () {
    const { counter } = await networkHelpers.loadFixture(deployCounterFixture);
    expect(await counter.x()).to.equal(0n);
  });
});
