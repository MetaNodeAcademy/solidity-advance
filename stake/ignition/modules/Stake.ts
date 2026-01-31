import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("StakeModule", (m) => {
    const rewardToken = m.contract("SSToken");
    const stake = m.contract("Stake");

    m.call(stake, "initialize", [rewardToken, 1, 9999, 10000]);

    return { rewardToken, stake };
});
