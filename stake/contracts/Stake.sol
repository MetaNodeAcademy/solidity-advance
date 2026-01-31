// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./SSToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Stake
 * @notice 质押合约：用于质押代币，并获得奖励
 */
contract Stake is Initializable, PausableUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    using Address for address;
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct PoolInfo {
        /**
         * @notice 代币地址
         */
        address tokenAddr;
        /**
         * @notice 质押代币数量
         */
        uint256 stakeAmount;
        /**
         * @notice 质押一个代币经过一个区块获得的奖励数量
         */
        uint256 perRewardCount;
        /**
         * @notice 上次计算奖励的区块
         */
        uint256 lastCalcBlock;
        /**
         * @notice 最小质押数量
         */
        uint256 minStakeCount;
        /**
         * @notice 权重
         */
        uint256 weight;
        /**
         * @notice 解除质押需要的区块数量
         */
        uint256 unlockBlockCount;
    }

    struct UnstakeInfo {
        /**
         * @notice 解除质押需要的区块号
         */
        uint256 blockNumber;
        /**
         * @notice 解除质押的代币数量
         */
        uint256 amount;
    }

    struct User {
        /**
         * @notice 质押代币数量
         */
        uint256 stakeAmount;
        /**
         * @notice 已获得的奖励数量
         */
        uint256 rewardAmount;
        /**
         * @notice 可领取的奖励数量
         */
        uint256 pendingAmount;
        /**
         * @notice 解除质押信息
         */
        UnstakeInfo[] unstakeInfos;
    }

    //-------------------------------------------变量定义-----------------------------------------------//

    /**
     * @notice 池子映射
     */
    mapping(address => bool) public poolMap;
    /**
     * @notice 资金池列表
     */
    PoolInfo[] public poolList;
    /**
     * @notice 用户质押信息(池子ID=>用户地址=>用户信息)
     */
    mapping(uint256 => mapping(address => User)) public userInfo;

    IERC20 public rewardToken;

    /**
     * @notice 总权重
     */
    uint256 public totalWeight;
    /**
     * @notice 开始区块
     */
    uint256 public startBlock;
    /**
     * @notice 结束区块
     */
    uint256 public endBlock;
    /**
     * @notice 每个区块的奖励数量
     */
    uint256 public rewardPerBlock;

    /**
     * @notice 超级管理员
     */
    bytes32 public ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /**
     * @notice 暂停角色
     */
    bytes32 public PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /**
     * @notice 升级角色
     */
    bytes32 public UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    //-------------------------------------------事件定义-----------------------------------------------//

    event SetRewardTokenEvent(IERC20 rewardToken);
    event SetStartBlockEvent(uint256 startBlock);
    event SetEndBlockEvent(uint256 endBlock);
    event SetRewardPerBlockEvent(uint256 rewardPerBlock);
    event SetPoolWeightEvent(uint256 indexed poolId, uint256 weight);
    event UpdatePoolInfoEvent(uint256 indexed poolId, uint256 minStakeCount, uint256 unlockBlockCount);

    event PoolAddedEvent(address indexed tokenAddr, uint256 weight, uint256 unlockBlockCount, uint256 minStakeCount);
    event StakeEvent(uint256 indexed poolId, address indexed user, uint256 amount);
    event UnstakeEvent(uint256 indexed poolId, address indexed user, uint256 amount);
    event WithdrawEvent(uint256 indexed poolId, address indexed user, uint256 amount);
    event ClaimEvent(uint256 indexed poolId, address indexed user, uint256 amount);

    //-------------------------------------------继承方法-----------------------------------------------//

    modifier checkPid(uint256 poolId) {
        require(poolId < poolList.length, "Invalid pool id");
        _;
    }

    function initialize(
        IERC20 _rewardToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardPerBlock
    ) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        rewardToken = _rewardToken;
        startBlock = _startBlock;
        endBlock = _endBlock;
        rewardPerBlock = _rewardPerBlock;
    }

    /**
     * @notice 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice 暂停合约
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    //-------------------------------------------外部方法-----------------------------------------------//

    /**
     * @notice 添加池子
     * @param tokenAddr 代币地址
     * @param weight 权重
     * @param minStakeCount 最小质押数量
     * @param unlockBlockCount 解除质押需要的区块数量
     * @return poolId 池子ID
     */
    function addPool(
        address tokenAddr,
        uint256 weight,
        uint256 minStakeCount,
        uint256 unlockBlockCount
    ) public onlyRole(ADMIN_ROLE) returns (uint256) {
        uint256 length = poolList.length;
        bool isExist = poolMap[tokenAddr];
        require(!isExist, "Pool already exists");
        require(weight > 0, "Invalid weight");
        require(minStakeCount > 0, "Invalid min stake count");
        require(unlockBlockCount > 0, "Invalid unlock block count");

        uint256 b = block.number > startBlock ? block.number : startBlock;
        poolMap[tokenAddr] = true;
        totalWeight = totalWeight + weight;
        poolList.push(
            PoolInfo({
                tokenAddr: tokenAddr,
                stakeAmount: 0,
                perRewardCount: 0,
                lastCalcBlock: b,
                weight: weight,
                unlockBlockCount: unlockBlockCount,
                minStakeCount: minStakeCount
            })
        );

        emit PoolAddedEvent(tokenAddr, weight, unlockBlockCount, minStakeCount);
        return length;
    }

    /**
     * @notice 质押
     * @param poolId 池子ID
     * @param amount 质押数量
     */
    function stake(uint256 poolId, uint256 amount) public payable checkPid(poolId) whenNotPaused {
        require(endBlock > block.number && block.number > startBlock, "Stake period has not started or ended");
        PoolInfo storage pool = poolList[poolId];
        if (msg.value > 0) {
            require(pool.tokenAddr == address(0), "ETH pool only support ETH");
            amount = msg.value;
        } else {
            require(amount > pool.minStakeCount, "Invalid amount");
            IERC20(pool.tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
        }

        updatePool(poolId);
        (bool success, uint256 value) = pool.stakeAmount.tryAdd(amount);
        require(success, "add operation overflow");
        pool.stakeAmount = value;

        User storage user = userInfo[poolId][msg.sender];
        (bool success2, uint256 value2) = user.stakeAmount.tryAdd(amount);
        require(success2, "add operation overflow");
        user.stakeAmount = value2;

        emit StakeEvent(poolId, msg.sender, amount);
    }

    /**
     * @notice 解除质押
     * @param poolId 池子ID
     * @param amount 解除质押数量
     */
    function unstake(uint256 poolId, uint256 amount) public checkPid(poolId) whenNotPaused {
        PoolInfo storage pool = poolList[poolId];
        User storage user = userInfo[poolId][msg.sender];
        require(amount <= user.stakeAmount, "Invalid amount");
        updatePool(poolId);

        user.stakeAmount = user.stakeAmount - amount;
        pool.stakeAmount = pool.stakeAmount - amount;

        user.unstakeInfos.push(UnstakeInfo({blockNumber: block.number + pool.unlockBlockCount, amount: amount}));
        emit UnstakeEvent(poolId, msg.sender, amount);
    }

    /**
     * @notice 提现
     * @param poolId 池子ID
     */
    function withdraw(uint256 poolId) public checkPid(poolId) whenNotPaused {
        PoolInfo storage pool = poolList[poolId];
        User storage user = userInfo[poolId][msg.sender];

        uint256 waitUnstakeAmount = 0;
        uint256 popNum = 0;
        uint256 len = user.unstakeInfos.length;
        for (uint256 i = 0; i < len; i++) {
            if (user.unstakeInfos[i].blockNumber <= block.number) {
                waitUnstakeAmount = waitUnstakeAmount + user.unstakeInfos[i].amount;
                popNum++;
            } else {
                break;
            }
        }

        for (uint256 i = 0; i < len - popNum; i++) {
            user.unstakeInfos[i] = user.unstakeInfos[i + popNum];
        }

        for (uint256 i = 0; i < popNum; i++) {
            user.unstakeInfos.pop();
        }

        if (waitUnstakeAmount > 0) {
            if (pool.tokenAddr == address(0)) {
                _safeTransferETH(msg.sender, waitUnstakeAmount);
            } else {
                IERC20(pool.tokenAddr).safeTransfer(msg.sender, waitUnstakeAmount);
            }
        }

        emit WithdrawEvent(poolId, msg.sender, waitUnstakeAmount);
    }

    /**
     * @notice 领取奖励
     * @param poolId 池子ID
     */
    function claim(uint256 poolId) public checkPid(poolId) whenNotPaused {
        updatePool(poolId);
        PoolInfo storage pool = poolList[poolId];
        User storage user = userInfo[poolId][msg.sender];
    }

    /**
     * @notice 设置奖励代币
     * @param _rewardToken 奖励代币地址
     */
    function setRewardToken(IERC20 _rewardToken) public onlyRole(ADMIN_ROLE) {
        require(address(_rewardToken) != address(0), "Invalid reward token");
        rewardToken = _rewardToken;
        emit SetRewardTokenEvent(_rewardToken);
    }

    /**
     * @notice 设置开始区块
     * @param _startBlock 开始区块
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock > 0, "Invalid start block");
        require(_startBlock < endBlock, "Start block must be less than end block");
        startBlock = _startBlock;
        emit SetStartBlockEvent(_startBlock);
    }

    /**
     * @notice 设置结束区块
     * @param _endBlock 结束区块
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(_endBlock > startBlock, "End block must be greater than start block");
        require(_endBlock > block.number, "End block must be greater than current block");
        endBlock = _endBlock;
        emit SetEndBlockEvent(_endBlock);
    }

    /**
     * @notice 设置每个区块的奖励数量
     * @param _rewardPerBlock 每个区块的奖励数量
     */
    function setRewardPerBlock(uint256 _rewardPerBlock) public onlyRole(ADMIN_ROLE) {
        require(_rewardPerBlock > 0, "Invalid reward per block");
        updateAllPool();
        rewardPerBlock = _rewardPerBlock;
        emit SetRewardPerBlockEvent(_rewardPerBlock);
    }

    /**
     * @notice 设置池子权重
     * @param poolId 池子ID
     * @param weight 权重
     * @param _updatePool 是否更新所有池子
     */
    function setPoolWeight(
        uint256 poolId,
        uint256 weight,
        bool _updatePool
    ) public checkPid(poolId) onlyRole(ADMIN_ROLE) {
        require(weight > 0, "Invalid weight");
        if (_updatePool) {
            updateAllPool();
        }

        PoolInfo storage pool = poolList[poolId];
        totalWeight = totalWeight - pool.weight + weight;
        pool.weight = weight;
        emit SetPoolWeightEvent(poolId, weight);
    }

    /**
     * @notice 更新池子信息
     * @param poolId 池子ID
     * @param minStakeCount 最小质押数量
     * @param unlockBlockCount 解除质押需要的区块数量
     */
    function updatePoolInfo(
        uint256 poolId,
        uint256 minStakeCount,
        uint256 unlockBlockCount
    ) public checkPid(poolId) onlyRole(ADMIN_ROLE) {
        require(minStakeCount > 0, "Invalid min stake count");
        require(unlockBlockCount > 0, "Invalid unlock block count");

        PoolInfo storage pool = poolList[poolId];
        pool.minStakeCount = minStakeCount;
        pool.unlockBlockCount = unlockBlockCount;
        emit UpdatePoolInfoEvent(poolId, minStakeCount, unlockBlockCount);
    }

    /**
     * @notice 获取池子数量
     * @return 池子数量
     */
    function poolLength() external view returns (uint256) {
        return poolList.length;
    }

    /**
     * @notice 获取用户在某池子的待领取奖励
     * @param poolId 池子ID
     * @param userAddr 用户地址
     * @return 待领取奖励数量
     */
    function getPendingReward(uint256 poolId, address userAddr) external view checkPid(poolId) returns (uint256) {
        PoolInfo memory pool = poolList[poolId];
        User memory user = userInfo[poolId][userAddr];
        uint256 perRewardCount = pool.perRewardCount;
        if (block.number > pool.lastCalcBlock && pool.stakeAmount > 0 && totalWeight > 0) {
            uint256 totalReward = _getMultiply(pool.lastCalcBlock, block.number);
            uint256 poolReward = (totalReward * pool.weight) / totalWeight;
        }
        return 0;
    }

    //-------------------------------------------内部方法-----------------------------------------------//

    /**
     * @notice 更新所有池子信息
     */
    function updateAllPool() internal {
        uint256 length = poolList.length;
        for (uint256 i = 0; i < length; i++) {
            updatePool(i);
        }
    }

    /**
     * @notice 更新池子信息
     * @param poolId 池子ID
     */
    function updatePool(uint256 poolId) internal {
        PoolInfo storage pool = poolList[poolId];
        if (block.number <= pool.lastCalcBlock) {
            return;
        }

        uint256 totalStake = pool.stakeAmount;
        if (totalStake > 0) {
            uint256 totalReward = _getMultiply(pool.lastCalcBlock, block.number);
            (bool success, uint256 value) = totalReward.tryMul(pool.weight);
            require(success, "multiply operation overflow");
            (bool success2, uint256 value2) = value.tryDiv(totalWeight);
            require(success2, "divide operation overflow");
            (bool success3, uint256 value3) = value2.tryMul(1 ether);
            require(success3, "multiply operation overflow");
            (bool success4, uint256 value4) = value3.tryDiv(totalStake);
            require(success4, "divide operation overflow");
            (bool success5, uint256 value5) = pool.perRewardCount.tryAdd(value4);
            require(success5, "add operation overflow");
            pool.perRewardCount = value5;
        }

        pool.lastCalcBlock = block.number;
    }

    /**
     * @notice 获取区块之间的奖励数量
     * @param _formBlock 开始区块
     * @param _endBlock 结束区块
     * @return 奖励数量
     */
    function _getMultiply(uint256 _formBlock, uint256 _endBlock) internal view returns (uint256) {
        require(_formBlock <= _endBlock, "invalid block number");
        if (_formBlock < startBlock) {
            _formBlock = startBlock;
        }
        if (_endBlock > endBlock) {
            _endBlock = endBlock;
        }

        (bool success, uint256 value) = (_endBlock - _formBlock).tryMul(rewardPerBlock);
        require(success, "multiply operation overflow");
        return value;
    }

    /**
     * @notice 安全ETH转账
     * @param to 接收地址
     * @param amount 转账数量
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, bytes memory data) = to.call{value: amount}("");
        require(success, "ETH transfer call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "ETH transfer not successful");
        }
    }

    /**
     * @notice 安全ERC20转账
     * @param to 接收地址
     * @param amount 转账数量
     */
    function _safeTransferERC20(address to, uint256 amount) internal {
        uint256 balance = rewardToken.balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        rewardToken.safeTransfer(to, amount);
    }

    /**
     * @notice 接收 ETH（用于 ETH 质押池）
     */
    receive() external payable {}
}
