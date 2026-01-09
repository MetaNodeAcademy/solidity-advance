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
     * @notice ETH 的池子ID
     */
    uint256 constant ETH_ID = 0;
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

        PoolInfo storage info = poolList[poolId];
        totalWeight = totalWeight - info.weight + weight;
        info.weight = weight;
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

        PoolInfo storage info = poolList[poolId];
        info.minStakeCount = minStakeCount;
        info.unlockBlockCount = unlockBlockCount;
        emit UpdatePoolInfoEvent(poolId, minStakeCount, unlockBlockCount);
    }

    /**
     * @notice 添加池子
     * @param tokenAddr 代币地址
     * @param weight 权重
     * @param minStakeCount 最小质押数量
     * @param unlockBlockCount 解除质押需要的区块数量
     */
    function addPool(
        address tokenAddr,
        uint256 weight,
        uint256 minStakeCount,
        uint256 unlockBlockCount
    ) public onlyRole(ADMIN_ROLE) {
        bool isExist = poolMap[tokenAddr];
        require(!isExist, "Pool already exists");
        poolMap[tokenAddr] = true;
        totalWeight = totalWeight + weight;
        poolList.push(
            PoolInfo({
                tokenAddr: tokenAddr,
                stakeAmount: 0,
                perRewardCount: 0,
                lastCalcBlock: block.number,
                weight: weight,
                unlockBlockCount: unlockBlockCount,
                minStakeCount: minStakeCount
            })
        );

        emit PoolAddedEvent(tokenAddr, weight, unlockBlockCount, minStakeCount);
    }

    function stake(uint256 amount) public {}

    function unstake(uint256 amount) public {}

    //-------------------------------------------内部方法-----------------------------------------------//

    function updateAllPool() internal {
        uint256 length = poolList.length;
        for (uint256 i = 0; i < length; i++) {
            updatePool(i);
        }
    }

    function updatePool(uint256 poolId) internal {
        PoolInfo memory info = poolList[poolId];
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
        (bool success, bytes memory data) = payable(to).call{value: amount}("");
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
        rewardToken.transfer(to, amount);
    }
}
