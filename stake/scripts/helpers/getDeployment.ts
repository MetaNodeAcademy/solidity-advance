import fs from "fs";
import path from "path";
import hre from "hardhat";

/**
 * 获取 Ignition 部署信息的辅助函数
 *
 * Ignition 部署信息保存在: ignition/deployments/{network}/{moduleName}.json
 */

export interface DeploymentInfo {
  address: string;
  contractName: string;
  [key: string]: any;
}

export interface IgnitionDeployment {
  id: string;
  contracts: {
    [contractName: string]: DeploymentInfo;
  };
  [key: string]: any;
}

/**
 * 读取 Ignition 部署文件
 * @param moduleName Ignition 模块名称（例如 "CounterModule"）
 * @param networkName 网络名称（默认 "hardhat"）
 * @returns 部署信息对象，如果不存在则返回 null
 */
export function readIgnitionDeployment(
  moduleName: string,
  networkName: string = "hardhat"
): IgnitionDeployment | null {
  try {
    const deploymentPath = path.join(
      hre.config.paths.ignition,
      "deployments",
      networkName,
      `${moduleName}.json`
    );

    if (!fs.existsSync(deploymentPath)) {
      return null;
    }

    const deploymentData = JSON.parse(fs.readFileSync(deploymentPath, "utf-8"));
    return deploymentData as IgnitionDeployment;
  } catch (error) {
    console.error(`Error reading deployment: ${error}`);
    return null;
  }
}

/**
 * 获取特定合约的部署地址
 * @param moduleName Ignition 模块名称
 * @param contractName 合约名称
 * @param networkName 网络名称（默认 "hardhat"）
 * @returns 合约地址，如果不存在则返回 null
 */
export function getDeploymentAddress(
  moduleName: string,
  contractName: string,
  networkName: string = "hardhat"
): string | null {
  const deployment = readIgnitionDeployment(moduleName, networkName);
  if (!deployment) {
    return null;
  }

  const contract = deployment.contracts?.[contractName];
  return contract?.address || null;
}

/**
 * 获取所有已部署的合约地址
 * @param moduleName Ignition 模块名称
 * @param networkName 网络名称（默认 "hardhat"）
 * @returns 合约名称到地址的映射对象
 */
export function getAllDeploymentAddresses(
  moduleName: string,
  networkName: string = "hardhat"
): Record<string, string> {
  const deployment = readIgnitionDeployment(moduleName, networkName);
  if (!deployment || !deployment.contracts) {
    return {};
  }

  const addresses: Record<string, string> = {};
  for (const [contractName, contractInfo] of Object.entries(
    deployment.contracts
  )) {
    if (contractInfo.address) {
      addresses[contractName] = contractInfo.address;
    }
  }

  return addresses;
}
