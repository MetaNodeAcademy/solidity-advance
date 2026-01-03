import { expect } from "chai";
import { network } from "hardhat";
import hre from "hardhat";
import { getDeploymentAddress } from "../scripts/helpers/getDeployment.js";

const { ethers, networkHelpers } = await network.connect();

/**
 * 在测试用例中获取 Ignition 自动保存的部署信息
 *
 * Ignition 会将部署信息保存到: ignition/deployments/{network}/{moduleName}.json
 *
 * 部署信息结构示例:
 * {
 *   "id": "CounterModule",
 *   "contracts": {
 *     "Counter": {
 *       "address": "0x...",
 *       "contractName": "Counter",
 *       ...
 *     }
 *   }
 * }
 */

// 方式2: 使用 fixture 函数，如果部署存在则使用，否则部署新合约
async function getCounterFixture() {
  // 尝试从 Ignition 部署中获取地址
  const deploymentAddress = getDeploymentAddress(
    "CounterModule",
    "Counter",
    "hardhat"
  );

  let counter;
  if (deploymentAddress) {
    // 如果部署存在，连接到已部署的合约
    const artifact = await hre.artifacts.readArtifact("Counter");
    counter = await ethers.getContractAt(artifact.abi, deploymentAddress);
    console.log(`Using deployed Counter at: ${deploymentAddress}`);
  } else {
    // 如果部署不存在，部署新合约
    counter = await ethers.deployContract("Counter");
    await counter.waitForDeployment();
    console.log(`Deployed new Counter at: ${await counter.getAddress()}`);
  }

  const deploymentBlockNumber = await ethers.provider.getBlockNumber();

  return { counter, deploymentBlockNumber };
}

describe("Counter with Ignition Deployment", function () {
  it("Should use deployed contract from Ignition if available", async function () {
    const { counter } = await networkHelpers.loadFixture(getCounterFixture);

    // 验证合约地址存在
    const address = await counter.getAddress();
    expect(address).to.be.a("string");
    expect(address).to.match(/^0x[a-fA-F0-9]{40}$/);

    // 测试合约功能
    await expect(counter.inc()).to.emit(counter, "Increment").withArgs(1n);
  });

  it("Should read contract state from deployment", async function () {
    const { counter } = await networkHelpers.loadFixture(getCounterFixture);

    // 读取合约状态
    const value = await counter.x();
    expect(value).to.be.a("bigint");
  });

  it("Should interact with deployed contract", async function () {
    const { counter } = await networkHelpers.loadFixture(getCounterFixture);

    const initialValue = await counter.x();
    await counter.inc();
    const newValue = await counter.x();

    expect(newValue).to.equal(initialValue + 1n);
  });
});

// 方式3: 直接读取部署文件并连接到合约（不使用 fixture）
describe("Counter Direct Deployment Read", function () {
  it("Should read and connect to Ignition deployment", async function () {
    const deploymentAddress = getDeploymentAddress(
      "CounterModule",
      "Counter",
      "hardhat"
    );

    if (!deploymentAddress) {
      // 如果部署不存在，跳过测试或部署新合约
      console.log("No deployment found, deploying new contract...");
      const counter = await ethers.deployContract("Counter");
      await counter.waitForDeployment();
      const address = await counter.getAddress();

      expect(address).to.be.a("string");
      return;
    }

    // 读取合约 artifact 并连接到已部署的合约
    const artifact = await hre.artifacts.readArtifact("Counter");
    const counter = await ethers.getContractAt(artifact.abi, deploymentAddress);

    // 验证连接成功
    const value = await counter.x();
    expect(value).to.be.a("bigint");
  });
});
